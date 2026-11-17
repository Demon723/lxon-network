#!/usr/bin/env python3
"""Genesis acceptance test. Exit 0 only if Besu encoded what we asked for.

Written BEFORE the generator, so the first run must fail with FileNotFoundError.

NEVER reads or prints private key material: it opens keys/pub-*.hex and keys/address-*.txt
only. The 725/726 validator IDENTITY is derived from those PUBLIC key files with eth_keys
and compared element-by-element and in order against the addresses RLP-decoded out of
`extraData`. The comparison deliberately does not use validator-addresses.txt: the same
pipeline wrote that file and the genesis, so agreeing with it would prove nothing.

This module also owns the expected genesis constants (BALANCE, EVM_GATES) and the RLP
decoder; make-genesis.py imports them, so the generator and the checker cannot drift.
"""
import json
import os
import re
import sys

from eth_keys import keys

BASE = os.path.dirname(os.path.abspath(__file__))
# Copied from production, not typed from memory. This is the third wrong copy of this literal in
# the project (the plan had 60 digits, the script had 65), so it was read out of
# lxon-evm-node/besu/genesis.qbft.json with:
#   python3 -c "import json;print({v['balance'] for v in json.load(open(
#       'lxon-evm-node/besu/genesis.qbft.json'))['alloc'].values()})"
# and the guard below refuses to import this module unless it is 64 hex digits and < 2**256.
BALANCE = "0x1337000000000000000000000000000000000000000000000000000000000000"
# The uint256 boundary is a hard limit, not cosmetics, so the constant is guarded at import
# time -- before make-genesis.py (which imports BALANCE from here) can write any genesis file.
def _check_balance_constant(balance):
    """Refuse to import this module on a BALANCE Besu cannot load.

    Round 1 shipped `0x1337` + 61 zeros: 65 hex digits = 260 bits. Every alloc entry inherited
    it and Besu aborted the genesis with "Argument is too large to represent a UInt256", so
    node-1 crash-looped at exit 2. The checker could not see it because it compares each alloc
    balance against this same constant, so a mistyped literal validates itself and a genesis no
    node can boot still reports GENESIS OK. A shape check (64 digits) plus an absolute range
    check (below 2**256) do not depend on the constant agreeing with itself.
    """
    digits = len(balance) - 2
    value = int(balance, 16)
    if digits != 64 or not (0 < value < 2 ** 256):
        raise ValueError(
            f"BALANCE has {digits} hex digits and is {value.bit_length()} bits. This guard checks "
            f"two things only: that it is exactly 64 hex digits, and that its value is in "
            f"(0, 2**256) -- i.e. that it is a well-formed non-zero uint256. It does not require "
            f"any particular mantissa, so do not read this as 'must be 0x1337 plus 60 zeros'; that "
            f"is the value the checker compares alloc entries against separately, and it comes from "
            f"alloc[*][\"balance\"] in lxon-evm-node/besu/genesis.qbft.json. A 65-digit literal like "
            f"round 1's is 260 bits and Besu rejects the genesis outright with 'Argument is too "
            f"large to represent a UInt256', which is why the count and the range are checked "
            f"here rather than trusting the constant to agree with itself. Fix the constant -- do "
            f"not edit this guard to make it pass.")
    return balance


_check_balance_constant(BALANCE)

# Verbatim from lxon-evm-node/besu/genesis.qbft.json, the gate set running on production 724.
# make-genesis.py imports this dict; the testbed must compile exactly what 724 compiles.
EVM_GATES = {
    "homesteadBlock": 0, "eip150Block": 0, "eip155Block": 0, "eip158Block": 0,
    "byzantiumBlock": 0, "constantinopleBlock": 0, "petersburgBlock": 0,
    "istanbulBlock": 0, "berlinBlock": 0, "londonBlock": 0,
    "shanghaiTime": 0, "cancunTime": 0,
}

# Which node keys must be the validators of each chain, in extraData order. Node 5 is the
# spare Task 3 votes in and must not appear in either genesis (it is simply not listed).
CHAIN_VALIDATOR_NODES = {"725": (1, 2, 3, 4), "726": (6,)}
# Every node key plus the deployer must be funded on both chains.
ALL_NODE_NUMBERS = (1, 2, 3, 4, 5, 6)
ALLOC_KEY_SHAPE = re.compile(r"\A[0-9a-f]{40}\Z")
PUB_KEY_SHAPE = re.compile(r"\A0x[0-9a-fA-F]{128}\Z")


def _rlp_payload(b, i):
    """Return (payload_bytes, next_index) for the RLP item starting at i."""
    x = b[i]
    if x < 0x80:
        return b[i:i + 1], i + 1
    if x < 0xB8:
        n = x - 0x80
        return b[i + 1:i + 1 + n], i + 1 + n
    if x < 0xC0:
        ln = x - 0xB7
        n = int.from_bytes(b[i + 1:i + 1 + ln], "big")
        s = i + 1 + ln
        return b[s:s + n], s + n
    raise ValueError("item is a list")


def validator_addresses(extra_data_hex):
    """QBFT genesis extraData is [vanity32, LIST<addr>, LIST, bytes, LIST]."""
    if not isinstance(extra_data_hex, str) or not extra_data_hex.startswith("0x"):
        raise ValueError("extraData must be a 0x-prefixed hex string")
    b = bytes.fromhex(extra_data_hex[2:])
    if not b:
        raise ValueError("extraData payload is empty")
    x = b[0]
    if x < 0xF8:
        n = x - 0xC0
        start = 1
    else:
        ln = x - 0xF7
        n = int.from_bytes(b[1:1 + ln], "big")
        start = 1 + ln
    body = b[start:start + n]
    i = 0
    items = []
    while i < len(body):
        x = body[i]
        if x < 0xC0:
            v, i = _rlp_payload(body, i)
            items.append(("bytes", v))
        else:
            if x < 0xF8:
                n = x - 0xC0
                s = i + 1
            else:
                ln = x - 0xF7
                n = int.from_bytes(body[i + 1:i + 1 + ln], "big")
                s = i + 1 + ln
            inner = body[s:s + n]
            j, subs = 0, []
            while j < len(inner):
                v, j = _rlp_payload(inner, j)
                subs.append(v)
            items.append(("list", subs))
            i = s + n
    if len(items) < 2:
        raise ValueError("extraData has fewer than 2 RLP items")
    assert items[0][0] == "bytes" and len(items[0][1]) == 32, "vanity must be 32 bytes"
    assert items[1][0] == "list", "second slot must be the validator list"
    return [v.hex() for v in items[1][1]]


def pub_key_bytes(name, text):
    """Shape guard for keys/pub-N.hex.

    The files are `0x` + 128 hex = the 64 raw bytes of the uncompressed public key WITHOUT
    the 65-byte `04` prefix (that is what eth_keys' PublicKey.to_hex() produces and what the
    committed operator configs store). Anything else -- notably a 0x + 64-hex value, the
    shape of a private key -- is rejected here instead of being copied verbatim into the
    committed 725/operator-config.json.
    """
    if not PUB_KEY_SHAPE.match(text):
        raise ValueError(
            f"{name} must be 0x + 128 hex (64-byte uncompressed public key, no 04 prefix); "
            f"got {len(text)} chars")
    return bytes.fromhex(text[2:])


def address_from_pub(name, text):
    """The validator address a public key file stands for, derived independently of
    keys/address-N.txt and of the genesis."""
    return "0x" + keys.PublicKey(pub_key_bytes(name, text)).to_address().removeprefix("0x").lower()


def _expected_validator_list(directory):
    """[(node number, address)] for the validators this chain's extraData must encode."""
    out = []
    for n in CHAIN_VALIDATOR_NODES[directory]:
        name = f"pub-{n}.hex"
        with open(os.path.join(BASE, "keys", name)) as fh:
            out.append((n, address_from_pub(name, fh.read().strip())))
    return out


def _funded_addresses():
    """[(label, address)] that must hold funds: node keys 1-6 plus the deployer EOA."""
    out = []
    for n in ALL_NODE_NUMBERS:
        name = f"pub-{n}.hex"
        with open(os.path.join(BASE, "keys", name)) as fh:
            out.append((f"node-{n}", address_from_pub(name, fh.read().strip())))
    with open(os.path.join(BASE, "keys", "deployer-address.txt")) as fh:
        out.append(("deployer", fh.read().strip()))
    return out


def _production_balances():
    """The alloc balances the genesis actually running on 724 uses, or None if unreadable (N3).

    `BALANCE` is compared against itself elsewhere: `make-genesis.py` writes it into every alloc
    entry and the check below compares each entry against the same constant, so a wrong-but-in-range
    literal validates itself and this whole file stays green on a mantissa nobody sourced. The only
    anchor that can catch that is the production lineage file, which is versioned next to this
    directory and is what `check-isolation.sh` section 8 already reads for the EVM gates.
    """
    path = os.path.join(BASE, os.pardir, "genesis.qbft.json")
    try:
        with open(path) as fh:
            prod = json.load(fh)
        return {str(v.get("balance", "")).lower() for v in prod["alloc"].values()}
    except Exception:  # noqa: BLE001 - a missing anchor is a named finding, never a crash
        return None


def check(path, chain_id, directory, funded_addresses):
    """Return (decoded validator addresses, error list) for one genesis file."""
    with open(path) as fh:
        g = json.load(fh)
    errs = []
    cid = g["config"]["chainId"]
    cid = int(cid, 16) if isinstance(cid, str) else cid
    if cid != chain_id:
        errs.append(f"chainId {cid} != {chain_id}")
    qbft = g["config"].get("qbft", {})
    if qbft.get("blockperiodseconds") != 3:
        errs.append(f"blockperiodseconds {qbft.get('blockperiodseconds')} != 3")
    if qbft.get("epochlength") != 30:
        errs.append(f"epochlength {qbft.get('epochlength')} != 30 (a vote must land in ~90s)")
    missing_gates = [k for k, v in EVM_GATES.items() if g["config"].get(k) != v]
    if missing_gates:
        errs.append(f"EVM gates not the production set: {missing_gates} (PUSH0/mcopy would not compile)")

    expected = _expected_validator_list(directory)
    want = [a.removeprefix("0x").lower() for _, a in expected]
    extra_data = g.get("extraData")
    addrs = []
    if not isinstance(extra_data, str) or extra_data in ("", "0x"):
        # Named failure, and it must not stop the other chain from being checked.
        errs.append(f"extraData is missing or empty ({extra_data!r}); this genesis can never seal")
    else:
        try:
            addrs = validator_addresses(extra_data)
        except Exception as exc:  # noqa: BLE001 - a decode failure is a finding, not a crash
            errs.append(f"extraData does not decode as QBFT validator data: {type(exc).__name__}: {exc}")
    if addrs != want:
        errs.append(
            f"extraData encodes {len(addrs)} validator(s) "
            f"{addrs}, expected exactly {len(want)} in this order: {want}")
        for i, (node_no, addr) in enumerate(expected):
            got = addrs[i] if i < len(addrs) else "<absent>"
            if got != addr.removeprefix("0x").lower():
                errs.append(
                    f"extraData validator slot {i} is 0x{got}, but keys/pub-{node_no}.hex derives to "
                    f"0x{addr.removeprefix('0x').lower()} -- node-{node_no} is the signer this slot needs")
                break

    alloc = g.get("alloc", {})
    odd_keys = [k for k in alloc if not ALLOC_KEY_SHAPE.match(k)]
    if odd_keys:
        errs.append(f"alloc keys must be lowercase unprefixed 40-hex, found: {odd_keys}")
    # N3, the external anchor. Everything below compares each alloc balance against `BALANCE`, and
    # `make-genesis.py` writes that same constant into every entry -- so a well-formed literal with
    # the wrong mantissa validates against itself and this file reports GENESIS OK. The only thing
    # that can see it is the genesis production actually runs, so require every alloc balance to be
    # one of production's. Reported once per chain, because an anchor that repeats the mistake of
    # the thing it checks is not an anchor.
    prod_bal = _production_balances()
    if prod_bal is None:
        errs.append(
            "cannot anchor alloc balances to the production lineage: "
            "lxon-evm-node/besu/genesis.qbft.json is missing or unreadable -- this is the only "
            "external check on BALANCE's magnitude, so refusing to guess instead of passing")
    else:
        off_anchor = sorted({str((v or {}).get("balance", "")).lower() for v in alloc.values()} - prod_bal)
        if off_anchor:
            errs.append(
                f"alloc balance(s) {off_anchor} are not balances the production genesis uses "
                f"(production uses {sorted(prod_bal)}); BALANCE has drifted from the 724 lineage and "
                f"the self-comparison below cannot see it")
    for label, addr in funded_addresses:
        key = addr.lower().removeprefix("0x")
        entry = alloc.get(key)
        if entry is None:
            errs.append(f"alloc missing funded address {label} 0x{key}")
            continue
        bal = (entry or {}).get("balance")
        try:
            wei = int(bal, 16)
        except (TypeError, ValueError):
            errs.append(f"alloc {label} 0x{key} has an unparsable balance {bal!r}")
            continue
        # Two checks, and the order matters. The comparison against BALANCE cannot catch a bad
        # BALANCE -- the generator imports the same constant from this module, so a mistyped literal
        # validates against itself and a genesis that Besu refuses to boot still reports
        # GENESIS OK (this happened: 65 hex digits, 260 bits, "Argument is too large to represent a
        # UInt256"). The range check is absolute, not comparative, so it catches the constant itself.
        if not (0 < wei < 2 ** 256):
            errs.append(
                f"alloc {label} 0x{key} balance {bal!r} is not a uint256 -- it has "
                f"{len(bal) - 2} hex digits where 64 is the maximum, so Besu aborts with "
                f"'Argument is too large to represent a UInt256'"
                if wei >= 2 ** 256 else
                f"alloc {label} 0x{key} has a zero balance; it can never send a transaction")
        if bal.lower() != BALANCE.lower():
            errs.append(
                f"alloc {label} 0x{key} balance {bal} != the production-magnitude allocation {BALANCE}")
    # The loop above only reaches the addresses this checker expects. A 257-bit balance on any
    # OTHER alloc entry -- added by hand, or left by a generator bug -- makes Besu refuse to load
    # the whole genesis, and the funded-address loop would report GENESIS OK without ever seeing
    # it. Same absolute predicate, applied to every entry, and it does not consult BALANCE, so it
    # cannot validate a constant against itself.
    funded_keys = {addr.lower().removeprefix("0x") for _, addr in funded_addresses}
    for key, entry in sorted(alloc.items()):
        if key in funded_keys:
            continue
        bal = (entry or {}).get("balance")
        try:
            wei = int(bal, 16)
        except (TypeError, ValueError):
            errs.append(f"alloc 0x{key} has an unparsable balance {bal!r}")
            continue
        if not (0 < wei < 2 ** 256):
            errs.append(
                f"alloc 0x{key} balance {bal!r} is not a well-formed uint256 "
                f"({(len(bal) - 2) if isinstance(bal, str) else '?'} hex digits, "
                f"{wei.bit_length()} bits); Besu aborts the genesis load for every node")
    return addrs, errs


def _run(label, path, chain_id, directory, funded_addresses):
    """Run one chain's check; a crash is a named failure and must not skip the other chain."""
    try:
        return check(path, chain_id, directory, funded_addresses)
    except FileNotFoundError as exc:
        return [], [f"required input is missing: {exc}"]
    except Exception as exc:  # noqa: BLE001
        return [], [f"check of {label} aborted before it could finish: {type(exc).__name__}: {exc}"]


def main():
    here = lambda *p: os.path.join(BASE, *p)
    ok = True
    try:
        funded = _funded_addresses()
    except (OSError, ValueError) as exc:
        print(f"FAIL keys: the public key files under keys/ are not usable: {exc}", file=sys.stderr)
        # N4's remaining path: this is the one exit that pre-empted both genesis checks, and it
        # printed a FAIL with no verdict line. A wrapper that greps stdout for the verdict (Task 2's
        # entrypoint) cannot distinguish "rejected" from "the checker itself broke", which is exactly
        # the confusion this round of fixes exists to remove.
        print("GENESIS REJECTED")
        return 1
    node_addr = {n: funded[i][1] for i, n in enumerate(ALL_NODE_NUMBERS)}

    # keys/address-N.txt must agree with the public key files they claim to describe: a
    # wrong address file would otherwise fund the genesis with addresses nobody controls.
    for n in ALL_NODE_NUMBERS:
        # Guarded: an unreadable address-N.txt used to raise straight out of main(), which killed
        # the run BEFORE either genesis was checked -- so a missing file produced a Python traceback
        # instead of a verdict, and a genuine 726 problem stayed invisible behind it.
        try:
            with open(here("keys", f"address-{n}.txt")) as fh:
                stored = fh.read().strip().lower()
        except OSError as exc:
            print(f"FAIL keys: address-{n}.txt cannot be read: {exc}", file=sys.stderr)
            ok = False
            continue
        if stored != node_addr[n].lower():
            print(f"FAIL keys: address-{n}.txt is {stored} but pub-{n}.hex derives to {node_addr[n]}",
                  file=sys.stderr)
            ok = False

    for label, chain_id, directory in (("725", 725, "725"), ("726", 726, "726")):
        addrs, errs = _run(label, here(directory, "genesis.json"), chain_id, directory, funded)
        print(f"{label} validators:",
              *[f"  {i}. 0x{a}" for i, a in enumerate(addrs)], sep="\n")
        for e in errs:
            print(f"FAIL {label}: {e}", file=sys.stderr)
            ok = False

    # Same reason as the address files above: this comparison is the last check in the run, and an
    # unguarded open() here turned a "GENESIS REJECTED" verdict into a traceback with the same exit
    # code but no summary line -- Task 2's operator could not tell a rejected genesis from a broken
    # checker. _run() already reported the missing file per chain; finish the verdict instead.
    try:
        with open(here("725", "genesis.json")) as fh:
            g725 = fh.read()
        with open(here("726", "genesis.json")) as fh:
            g726 = fh.read()
    except OSError as exc:
        print(f"FAIL: cannot compare the two genesis files: {exc}", file=sys.stderr)
        print("GENESIS REJECTED")
        return 1
    if g725 == g726:
        print("FAIL: 725 and 726 genesis are byte-identical", file=sys.stderr)
        ok = False
    print("GENESIS OK" if ok else "GENESIS REJECTED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
