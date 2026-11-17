#!/usr/bin/env python3
"""Was there ever a swap on the wLXON/USDC pair, and which router does the pool's own history use?

Read-only: eth_getStorageAt, eth_getLogs, eth_getTransactionByHash. Windows are chunked because the
public endpoints cap log ranges (publicnode states 10,000 blocks; drpc and 1rpc fail without saying
their cap).
"""
import json
import subprocess
import sys

PUB = "https://polygon-bor-rpc.publicnode.com"
DRPC = "https://polygon.drpc.org"
PAIR = "0x8bFB69eD898654D49cCBB59B7E594280dF4CB8fd"
USDC = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
WLX = "0x7A3c0C34f157EfDD3E4913c5224C15E645469093"
RTR = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
SYNC = "0x1c411e9a96e071241c2f21f7726b17ae89eaca84808d007785ae7fe13642f5e1"
POOL_CREATED = 96349486          # add-liquidity block, from the launch record
ADD_LIQ_TX = "0x6ce2ef2c3f5c91ab73fe675b998268a8f3caacf8fc8d74862b4ad1a0995eb2fe"


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    out = subprocess.run(["curl", "-s", "-m", "60", "-X", "POST", "-H", "content-type: application/json",
                          "-d", body, url], capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
    except Exception:
        return {"_raw": out[:200]}
    return {"result": d["result"]} if "result" in d else {"_err": d.get("error", {})}


def pad(a):
    return "0x" + a[2:].lower().zfill(64)


def chunked_logs(address, topics, lo, hi, size=9000):
    total, hits, errors = 0, [], 0
    for start in range(lo, hi, size):
        end = min(start + size - 1, hi)
        r = rpc(PUB, "eth_getLogs", [{"fromBlock": hex(start), "toBlock": hex(end),
                                      "address": address, "topics": topics}])
        if "_err" in r:
            errors += 1
            continue
        total += len(r["result"])
        hits.extend(r["result"])
    return total, hits, errors


def main():
    h = int(rpc(PUB, "eth_blockNumber", [])["result"], 16)
    print(f"head = {h}; pool created at {POOL_CREATED}; blocks since = {h - POOL_CREATED}")

    print("\n-- which contract did the add-liquidity transaction call? --")
    tx = rpc(DRPC, "eth_getTransactionByHash", [ADD_LIQ_TX]).get("result") or {}
    print("   to =", tx.get("to"), "  (QuickSwap V2 router =", RTR.lower(), ")")
    print("   from =", tx.get("from"), " value =", tx.get("value"))

    print("\n-- pair storage slots 0..11 (V2 pair layout) --")
    for i in range(12):
        v = rpc(DRPC, "eth_getStorageAt", [PAIR, hex(i), "latest"]).get("result")
        n = int(v, 16)
        note = ""
        if i == 8 and n:
            r0 = n & (2 ** 112 - 1)
            r1 = (n >> 112) & (2 ** 112 - 1)
            ts = (n >> 224) & (2 ** 32 - 1)
            note = f"  reserve0={r0/1e6:.6f} reserve1={r1/1e18:.6f} tsLast={ts}"
        print(f"   slot{i:<2} = {v[:34]}{'…' if len(v) > 34 else ''}  dec={n}{note}")

    print("\n-- USDC Transfer events where the PAIR is the sender (a swap pays out from the pool) --")
    n, hits, err = chunked_logs(USDC, [TRANSFER, pad(PAIR), None], POOL_CREATED + 1, h)
    print(f"   count={n} (failed ranges={err})")
    for lg in hits[:8]:
        to = "0x" + lg["topics"][2][-40:]
        print(f"     block {lg['blockNumber']} -> {to} amount={int(lg['data'],16)/1e6:.6f} USDC")

    print("\n-- wLXON Transfer events where the PAIR is the recipient (a swap pays in to the pool) --")
    n2, hits2, err2 = chunked_logs(WLX, [TRANSFER, None, pad(PAIR)], POOL_CREATED + 1, h)
    print(f"   count={n2} (failed ranges={err2})")
    for lg in hits2[:8]:
        frm = "0x" + lg["topics"][1][-40:]
        print(f"     block {lg['blockNumber']} <- {frm} amount={int(lg['data'],16)/1e18:.6f} wLXON")

    print("\n-- pair Sync events (a swap calls sync at the end of every swap) --")
    n3, hits3, err3 = chunked_logs(PAIR, [SYNC], POOL_CREATED + 1, h)
    print(f"   count={n3} (failed ranges={err3})")

    print("\n-- who holds wLXON, and what is live allowance to the router for the top holders --")
    n4, hits4, _ = chunked_logs(WLX, [TRANSFER, None, None], POOL_CREATED + 1, h)
    print(f"   wLXON transfers in range: {n4}")


if __name__ == "__main__":
    sys.exit(main())
