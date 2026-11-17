#!/usr/bin/env python3
"""Find the legacy wLXON's ERC20 storage layout empirically on a fork.

No compiled artifact exists for 0xB2CfeCb2… in either repo (measured: no build in either repo matches its
3,343 deployed bytes), so the layout cannot be read from a .json -- it has to be derived from the chain and
then PROVEN by writing. Derivation alone is a guess: the convention (name, symbol, decimals, totalSupply,
balances, allowances) is common, and a token that packs `paused` next to `decimals` shifts every mapping
slot after it, which would make a balance write land in someone else's allowance.

Proof used here: write a value at the derived balance slot for a fresh address and check the contract's own
balanceOf() agrees. That is the contract answering, not this script.
"""
import json, subprocess, sys

RPC = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8551"
LEGACY = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6"

def rpc(method, *params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": list(params)})
    p = subprocess.run(["curl", "-s", "-X", "POST", "-H", "content-type: application/json", "-d", body, RPC],
                       capture_output=True, text=True)
    d = json.loads(p.stdout)
    if "error" in d:
        raise RuntimeError("%s -> %s" % (method, d["error"]))
    return d["result"]

want = int(rpc("eth_call", {"to": LEGACY, "data": "0x18160ddd"}, "latest"), 16)
print("totalSupply() = %d  (0x%x)" % (want, want))

ts_slot = None
for s in range(0, 16):
    v = int(rpc("eth_getStorageAt", LEGACY, hex(s), "latest"), 16)
    if v == want:
        ts_slot = s
        print("slot %d holds exactly totalSupply -> that is the _totalSupply slot" % s)
        break
if ts_slot is None:
    print("no slot 0..15 equals totalSupply: the token may compute supply, or use a non-standard layout")
    sys.exit(2)

# Candidate balances-mapping slots: the convention says the next slot after totalSupply; anything within
# +/-3 is worth trying, and only one should agree with a real balanceOf().
# Corroborate the layout hypothesis before writing anything: OpenZeppelin 5.x ERC20 is
# {0: _balances, 1: _allowances, 2: _totalSupply, 3: _name, 4: _symbol}, and totalSupply landing on slot 2
# is exactly that. Decoding slots 3 and 4 as strings either confirms it or kills it -- and a mapping slot
# guessed from a convention is how a balance write lands inside somebody's allowance.
def as_string(h):
    v = int(h, 16)
    if v == 0:
        return None
    raw = v.to_bytes(32, "big")
    length = raw[-1]
    if 0 < length <= 31 and raw[-2 - length:-1] == b"":
        pass
    # OZ ShortStrings packing: the length sits in the final byte, the text just before it.
    try:
        return raw[:length].decode("utf-8")
    except Exception:
        return None

for s in range(0, 6):
    h = rpc("eth_getStorageAt", LEGACY, hex(s), "latest")
    print("  slot %d = %s%s" % (s, h, ("  (decodes as %r)" % as_string(h)) if as_string(h) else ""))

probe = "0x1111111111111111111111111111111111111111"
print("candidates: slots %s (adjacent to totalSupply at %d)" % ([0, ts_slot + 1, ts_slot - 1, ts_slot + 2], ts_slot))

def bal_slot_addr(member_slot, addr):
    a = addr.lower().replace("0x", "").rjust(64, "0")
    m = hex(member_slot)[2:].rjust(64, "0")
    # keccak256(abi.encode(address, uint256)) == keccak of two packed 32-byte words
    inp = "0x" + a + m
    out = subprocess.run(["cast", "keccak", inp], capture_output=True, text=True).stdout.strip()
    return out

def w32(v):
    """32-byte hex word. anvil_setStorageAt rejects an unpadded value outright with
    `invalid string length` -- measured -- so a bare hex(1234567) is not a storage word."""
    return "0x" + hex(int(v))[2:].rjust(64, "0")

for cand in [0, ts_slot + 1, ts_slot - 1, ts_slot + 2, ts_slot + 3]:
    slot = bal_slot_addr(cand, probe)
    before = int(rpc("eth_getStorageAt", LEGACY, slot, "latest"), 16)
    rpc("anvil_setStorageAt", LEGACY, slot, w32(1234567))
    got = int(rpc("eth_call", {"to": LEGACY, "data": "0x70a08231" + probe[2:].lower().rjust(64, "0")}, "latest"), 16)
    rpc("anvil_setStorageAt", LEGACY, slot, w32(before))
    ok = (got == 1234567)
    print("  balances mapping at slot %d: wrote 1234567 -> balanceOf() says %d  %s"
          % (cand, got, "<-- THE LAYOUT" if ok else "(no)"))
    if ok:
        print(json.dumps({"totalSupplySlot": ts_slot, "balancesSlot": cand}))
        sys.exit(0)
print("no candidate slot produced a balanceOf() that agreed -- do not write balances against this token")
sys.exit(3)
