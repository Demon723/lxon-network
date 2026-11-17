#!/usr/bin/env python3
"""
Compute the block-0 hash of an LXON QBFT genesis, and rebuild that genesis with a
different validator address.

Self-checking by construction: `--control` reproduces the hash that the live node reported
for its own block 0 (0x6c931dff…, recorded in the 2026-11-02 migration bundle manifest).
If the RLP header encoding or the Cancun field list were wrong, that number would not come
back, and nothing downstream should trust the "new" hash either.

keccak is delegated to `cast keccak` (this machine's python 3.14 has no keccak binding).
"""
import json, subprocess, sys, argparse, re

HEXINT = lambda s: int(s, 16) if isinstance(s, str) else int(s)


def rb(h):
    """hex string -> raw bytes"""
    h = h[2:] if h.startswith('0x') else h
    if len(h) % 2:
        h = '0' + h
    return bytes.fromhex(h)


def enc_bytes(b):
    if len(b) == 1 and b[0] < 0x80:
        return b
    if len(b) <= 55:
        return bytes([0x80 + len(b)]) + b
    lb = len(b).to_bytes((len(b).bit_length() + 7) // 8, 'big')
    return bytes([0xB7 + len(lb)]) + lb + b


def enc_list(items):
    payload = b''.join(items)
    if len(payload) <= 55:
        return bytes([0xC0 + len(payload)]) + payload
    lb = len(payload).to_bytes((len(payload).bit_length() + 7) // 8, 'big')
    return bytes([0xF7 + len(lb)]) + lb + payload


def enc_int(v):
    """Integer -> minimal big-endian bytes -> RLP (0 becomes the empty string, 0x80)."""
    return enc_bytes(b'' if v == 0 else v.to_bytes((v.bit_length() + 7) // 8, 'big'))


def header_rlp(h):
    """
    Header field list, extended only by fields the block itself reports — i.e. the same
    fork-activation rule the client used. Pre-London blocks (Polygon block 0) stop at nonce;
    a Cancun-at-0 genesis (chain 724) carries baseFee + withdrawals + blob + beacon root.

    Every field is individually RLP-framed before the list is assembled; passing raw bytes
    straight into enc_list silently corrupts empty ints and 32-byte hashes.
    """
    f = [
        rb(h['parentHash']), rb(h['sha3Uncles']), rb(h['miner']),
        rb(h['stateRoot']), rb(h['transactionsRoot']), rb(h['receiptsRoot']),
        rb(h['logsBloom']),
        HEXINT(h['difficulty']), HEXINT(h['number']),
        HEXINT(h['gasLimit']), HEXINT(h['gasUsed']), HEXINT(h['timestamp']),
        rb(h['extraData']), rb(h['mixHash']), rb(h['nonce']),
    ]
    out = []
    for i, x in enumerate(f):
        out.append(enc_int(x) if isinstance(x, int) else enc_bytes(x))
    for k in ('baseFeePerGas', 'withdrawalsRoot', 'blobGasUsed', 'excessBlobGas',
              'parentBeaconBlockRoot'):
        if k in h and h[k] is not None:
            out.append(enc_int(HEXINT(h[k])) if k in ('baseFeePerGas', 'blobGasUsed', 'excessBlobGas')
                       else enc_bytes(rb(h[k])))
    return enc_list(out)


def keccak(data_hex):
    out = subprocess.run(['cast', 'keccak', '0x' + data_hex.lstrip('0x')],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def build_extradata(validator_addr, template):
    """
    Reproduce the QBFT extraData byte layout with a new validator address.

    template must be the known-good 60-byte layout (120 hex chars):
      f83a | a0 + 32B vanity | d5 | 94 + 20B address | c0 | 80 | c0
    Lengths are unchanged, so only the 20 address bytes differ.
    """
    t = template[2:] if template.startswith('0x') else template
    prefix, addr_slot, suffix = t[:72], t[72:114], t[114:]
    assert prefix.startswith('f83aa0') and len(prefix) == 72, 'unexpected extraData prefix'
    assert addr_slot.startswith('94') and len(addr_slot) == 42, 'unexpected validator slot'
    assert suffix == 'c080c0', 'unexpected extraData tail: %s' % suffix
    new = validator_addr.lower().replace('0x', '')
    if len(new) != 40 or not re.fullmatch(r'[0-9a-f]{40}', new):
        raise ValueError('validator address must be 40 hex chars, got %r' % validator_addr)
    return '0x' + prefix + '94' + new + suffix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('genesis', help='genesis json to base the calculation on')
    ap.add_argument('--control', help='header json; recomputes its own hash and compares')
    ap.add_argument('--set-validator', help='validator address to rotate in')
    ap.add_argument('--write', help='path to write the rotated genesis')
    a = ap.parse_args()

    g = json.load(open(a.genesis))

    if a.control:
        h = json.load(open(a.control))
        h = h['result'] if 'result' in h else h
        got = keccak(header_rlp(h).hex())
        want = h['hash']
        print('CONTROL  recorded block-0 hash : %s' % want)
        print('CONTROL  recomputed here       : %s' % got)
        print('CONTROL  encoder match        : %s' % ('YES' if got == want else 'NO'))
        if got != want:
            print('ABORT: the header encoder does not reproduce the recorded hash. '
                  'Treat every number below as unverified.', file=sys.stderr)
            return 1

    if a.set_validator:
        ed = build_extradata(a.set_validator, g['extraData'])
        # round-trip: the layout builder must regenerate the original bytes when handed the
        # original address, or the "rotation" is really a corruption of the field
        orig_addr = re.search(r'94([0-9a-f]{40})', g['extraData'].lstrip('0x')).group(1)
        rt = build_extradata(orig_addr, g['extraData'])
        same = (rt.lower() == g['extraData'].lower())
        print('ROUNDTRIP rebuild(original validator) == file : %s' % ('YES' if same else 'NO'))
        if not same:
            print('ABORT: extraData builder is not idempotent on the known-good input.', file=sys.stderr)
            return 1
        g2 = dict(g)
        g2['extraData'] = ed
        h2 = dict(json.load(open(a.control))['result']) if a.control else None
        if h2:
            h2['extraData'] = ed
            newhash = keccak(header_rlp(h2).hex())
            print('NEW validator    : %s' % a.set_validator)
            print('NEW extraData    : %s' % ed)
            print('NEW block-0 hash : %s' % newhash)
        if a.write:
            json.dump(g2, open(a.write, 'w'), indent=2)
            open(a.write, 'a').write('\n')
            print('WROTE            : %s' % a.write)
    return 0


if __name__ == '__main__':
    sys.exit(main())
