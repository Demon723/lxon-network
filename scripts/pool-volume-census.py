#!/usr/bin/env python3
"""Real, on-chain volume census for a QuickSwap V2 pair -- measures volume, never manufactures it.

Why a census and not the reserve timestamp: `blockTimestampReserved` frozen at the add-liquidity block proves
no reserve-changing event happened since, which is a strong property, but it is an inference from one slot.
Counting the pair's own event logs from its creation block to head is the direct measurement, and it can
report the gross flow split by direction.

Completeness is asserted, not assumed, by three gates:
  * every chunk must return without error -- a failed range silently shrinks the window and still prints 0;
  * Swap/Sync/Mint/Burn must satisfy the V2 invariant: every liquidity or swap event emits exactly one Sync,
    so Sync == Mint + Burn + Swap. A census that misses logs breaks this and says so;
  * a CONTROL scan against an actively traded pair over the same RPC must find Swaps, proving the method
    detects volume when volume exists.

Read-only. curl drives the HTTP because this machine's python 3.14 has no trust store.
"""
import subprocess, json, sys, time

RPC = sys.argv[1] if len(sys.argv) > 1 else "https://polygon-bor-rpc.publicnode.com"  # override: argv[1]
PAIR = "0x8bfb69ed898654d49ccbb59b7e594280df4cb8fd"   # wLXON / USDC.e on 137
FROM = 96349486                                       # the add-liquidity block, from the deployment record
CTRL_PAIR = "0x2cF7252e74036d1Da831d11089D326296e64a728"  # USDC.e / USDT0 -- a pool that trades
CTRL_CHUNKS = 1

def sig_topic(sig):
    """topic0 computed by cast every run -- a hand-typed event hash is how a census silently matches nothing."""
    r = subprocess.run(["cast", "sig-event", sig], capture_output=True, text=True).stdout.strip()
    assert r.startswith("0x") and len(r) == 66, "cast sig-event did not answer for %s: %r" % (sig, r)
    return r.lower()


# The four signatures below are the ones the CHAIN proved, not the ones I remembered. My first pass used
# "Sync(address,uint256,uint256)" and "Mint(address,uint256,uint256,uint256)" -- both legal-looking, both the
# wrong arity for a Uniswap V2 pair -- and the census then reported "Mint 0, Sync 0" for a pool that had
# demonstrably emitted one of each, making the completeness invariant 0 == 0 and vacuously green. The
# creation-block logs settled it: topic0 0x1c411e9a... = keccak256("Sync(uint112,uint112)") with no sender
# topic, and 0x4c209b5f... = keccak256("Mint(address,uint256,uint256)").
SWAP = sig_topic("Swap(address,uint256,uint256,uint256,uint256,address)")
SYNC = sig_topic("Sync(uint112,uint112)")
MINT = sig_topic("Mint(address,uint256,uint256)")
BURN = sig_topic("Burn(address,uint256,uint256,address)")
TRANSFER = sig_topic("Transfer(address,address,uint256)")
TOPICS = {SWAP: "Swap", SYNC: "Sync", MINT: "Mint", BURN: "Burn", TRANSFER: "Transfer"}


def rpc(method, params, tries=3):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    for a in range(tries):
        r = subprocess.run(["curl", "-s", "-m", "40", "-X", "POST", "-H",
                            "content-type: application/json", "-d", body, RPC],
                           capture_output=True, text=True)
        try:
            d = json.loads(r.stdout)
            if "result" in d:
                return d["result"], None
            return None, d.get("error", {}).get("message", "no-result")[:160]
        except Exception:
            time.sleep(1.5)
    return None, "curl/json failed after %d tries: %s" % (tries, (r.stdout or "")[:120])


def head():
    v, e = rpc("eth_blockNumber", [])
    if v is None:
        sys.exit("REFUSE: cannot read head (%s) -- a census with no denominator is not a census" % e)
    return int(v, 16)


def scan(address, start, stop):
    """Chunked eth_getLogs. Returns (logs, failures, chunks)."""
    logs, fails, chunks = [], [], 0
    step = 10000
    a = start
    while a <= stop:
        b = min(a + step - 1, stop)
        v, e = rpc("eth_getLogs", [{"address": address,
                                    "fromBlock": hex(a), "toBlock": hex(b)}])
        if v is None:
            # halve once before declaring failure, then abort loudly rather than continuing quietly
            if b - a > 1000:
                step = (b - a) // 2
                continue
            fails.append((a, b, e))
        else:
            logs.extend(v)
        chunks += 1
        a = b + 1
        step = 10000
    return logs, fails, chunks


def u256(h, i):
    return int(h[64 * i + 2:64 * (i + 1)], 16)


H = head()
print("RPC          %s" % RPC)
print("creation block  %d  (the add-liquidity block, from the deployment record)" % FROM)
print("head block    %d" % H)
print("range scanned %d blocks" % (H - FROM))
print()
print("scanning %s ..." % PAIR)
logs, fails, chunks = scan(PAIR, FROM, H)
print("  chunks: %d   failed chunks: %d" % (chunks, len(fails)))
if fails:
    print("  REFUSE: %d ranges failed; the counts below would be understated, not zero." % len(fails))
    for f in fails[:5]:
        print("    %s" % (f,))
    sys.exit(1)

by = {}
swaps = []
for L in logs:
    t0 = (L.get("topics") or ["0x" + "00" * 32])[0].lower()
    name = TOPICS.get(t0, "other:" + t0[:10])
    by[name] = by.get(name, 0) + 1
    if name == "Swap":
        d = (L.get("data") or "0x")[2:]
        swaps.append((int(L["blockNumber"], 16), u256(d, 1), u256(d, 2), u256(d, 3), u256(d, 4)))

print("  log counts by event:")
for k in sorted(by, key=lambda x: -by[x]):
    print("    %-10s %d" % (k, by[k]))
print("  total logs from this pair since creation: %d" % len(logs))
print()
if swaps:
    gross0 = sum(s[1] + s[3] for s in swaps) / 1e6   # token0 leg = USDC.e, 6 decimals
    gross1 = sum(s[2] + s[4] for s in swaps) / 1e18  # token1 leg = wLXON, 18 decimals
    print("VOLUME MEASURED: %d Swap events, gross USDC.e flow $%.2f, gross wLXON flow %.4f" % (len(swaps), gross0, gross1))
else:
    print("VOLUME MEASURED: 0 Swap events between the creation block and head.")
print("Invariant check (V2: every Mint/Burn/Swap emits exactly one Sync): Mint+Burn+Swap = %d, Sync = %d -> %s"
      % (by.get("Mint", 0) + by.get("Burn", 0) + len(swaps), by.get("Sync", 0),
         "CONSISTENT" if by.get("Mint", 0) + by.get("Burn", 0) + len(swaps) == by.get("Sync", 0) else "BROKEN -- the scan missed logs"))
print()
print("CONTROL: the same scan against %s (USDC.e/USDT0, which DexScreener reports trading ~1,268 times in 24 h)" % CTRL_PAIR)
cl, cf, cc = scan(CTRL_PAIR, H - 9999, H)
cswap = sum(1 for L in cl if (L.get("topics") or [""])[0].lower() == SWAP)
print("  chunks %d, failed %d, logs %d, Swap events %d" % (cc, len(cf), len(cl), cswap))
print("  -> %s" % ("CONTROL FOUND VOLUME, so a zero above is a measurement and not a blind spot"
                   if cswap > 0 else
                   "CONTROL ALSO FOUND NOTHING -- the method is blind, do NOT publish the zero"))
print()
# Signature-liveness gate: a topic0 that matches NOTHING anywhere is more likely a wrong signature string than
# a true absence -- which is exactly how the first pass of this script produced a green 0 == 0 invariant.
seen = set((L.get("topics") or [""])[0].lower() for L in logs + cl)
print("signature liveness (each topic0 must be observed on at least one pool):")
dead = []
for t, name in TOPICS.items():
    ok = t in seen
    print("    %-9s %s  %s" % (name, "OBSERVED" if ok else "NEVER MATCHED", t[:18] + "…"))
    if not ok:
        dead.append(name)
if dead:
    print("  WARNING: %s never matched on either pool. Either that event genuinely has not fired on these two"
          % ", ".join(dead))
    print("  pairs (Burn and Swap both qualify on a pool with no trades), or the signature string is wrong.")
    print("  Distinguish them by firing it: Swap is proven live by the CONTROL pool's %d Swap logs above." % cswap)
