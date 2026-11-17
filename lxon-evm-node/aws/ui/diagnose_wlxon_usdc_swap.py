#!/usr/bin/env python3
"""Find who approved the QuickSwap V2 router to spend wLXON, then simulate the swap read-only.

curl drives the RPC (python 3.14 on this machine has no CA store). Log ranges are kept small because
drpc and 1rpc cap them silently; publicnode states a 10,000-block cap and is used for the wide scan.
"""
import json
import subprocess

DRPC = "https://polygon.drpc.org"
PUB = "https://polygon-bor-rpc.publicnode.com"
WLX = "0x7A3c0C34f157EfDD3E4913c5224C15E645469093"
USDC = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
RTR = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"
PAIR = "0x8bFB69eD898654D49cCBB59B7E594280dF4CB8fd"
APPROVAL = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd031c0f7b2291e5b200ac8c7c3b9875"


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    out = subprocess.run(["curl", "-s", "-m", "60", "-X", "POST", "-H", "content-type: application/json",
                          "-d", body, url], capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
    except Exception:
        return {"_raw": out[:200]}
    if "error" in d:
        return {"_err": d["error"]}
    return {"result": d.get("result")}


def head(url):
    return int(rpc(url, "eth_blockNumber", [])["result"], 16)


def pad(a):
    return a[2:].lower().zfill(64)


def call(to, data, frm=None, url=DRPC):
    p = {"to": to, "data": data}
    if frm:
        p["from"] = frm
    r = rpc(url, "eth_call", [p, "latest"])
    if "_err" in r:
        return ("REVERT", r["_err"].get("data"), r["_err"].get("message"))
    return ("OK", r["result"])


def main():
    h = head(PUB)
    print(f"publicnode head = {h} (0x{h:x})")

    # 1) Approvals of wLXON with the router as spender, scanned backwards in bounded windows.
    found = []
    spans = [(h - 4999, h), (h - 9999, h - 5000)]
    for lo, hi in spans:
        r = rpc(PUB, "eth_getLogs", [{"fromBlock": hex(lo), "toBlock": hex(hi), "address": WLX,
                                      "topics": [APPROVAL, None, "0x" + pad(RTR)]}])
        if "_err" in r:
            print(f"  logs {lo}..{hi}: ERROR {r['_err']}")
            continue
        for lg in r["result"]:
            owner = "0x" + lg["topics"][1][-40:]
            amt = int(lg["data"], 16)
            found.append((owner, amt, int(lg["blockNumber"], 16)))
        print(f"  logs {lo}..{hi}: {len(r['result'])} approvals of wLXON naming the router")

    # also approvals *of USDC* to the router, for the buy direction
    for lo, hi in [(h - 4999, h)]:
        r = rpc(PUB, "eth_getLogs", [{"fromBlock": hex(lo), "toBlock": hex(hi), "address": USDC,
                                      "topics": [APPROVAL, None, "0x" + pad(RTR)]}])
        if "_err" not in r:
            print(f"  logs {lo}..{hi}: {len(r['result'])} USDC approvals naming the router")

    print()
    # 2) balances and the live allowance for each owner found
    holders = []
    for owner, amt, blk in found:
        bal = call(WLX, "0x70a08231" + pad(owner))
        alw = call(WLX, "0xdd62ed3e" + pad(owner) + pad(RTR))
        b = int(bal[1], 16) if bal[0] == "OK" else None
        a = int(alw[1], 16) if alw[0] == "OK" else None
        holders.append((owner, b, a))
        print(f"  holder {owner}  balance={b/1e18 if b else b:.6f}  allowance_to_router={(a or 0)/1e18:.6f}")

    print()
    # 3) simulate the swap read-only from a holder that still has allowance, at three minOut settings
    cand = [x for x in holders if x[2] and x[1]]
    if not cand:
        print("  no holder with both balance and live allowance was found in the scanned window; "
              "simulation skipped (that is a NOT RUN, not a verdict)")
    for owner, bal, alw in cand[:2]:
        amount_in = min(10 ** 18, bal, alw)          # 1 wLXON, capped by balance/allowance
        quote = call(RTR, "0xd06ca61f" + f"{amount_in:064x}" + f"{0x40:064x}" + f"{2:064x}"
                     + pad(WLX) + pad(USDC))
        out = int(quote[1][-64:], 16) if quote[0] == "OK" else None
        spot = call(PAIR, "0x0902f1ac")
        r0 = int(spot[1][2:66], 16) if spot[0] == "OK" else None      # USDC (token0)
        r1 = int(spot[1][66:130], 16) if spot[0] == "OK" else None    # wLXON (token1)
        ideal = int(amount_in * r0 / r1) if r0 and r1 else None
        print(f"  from {owner}: amountIn={amount_in/1e18}  quote={out/1e6 if out else out} USDC  "
              f"spot-ideal={ideal/1e6 if ideal else ideal} USDC  (impact {100*(1-out/ideal):.1f}%)"
              if out and ideal else f"  from {owner}: quote unavailable {quote}")

        for label, minout in [("minOut=0", 0), ("minOut=99.5% of quote", int(out * 995 // 1000)),
                              ("minOut=spot price (0.1% slippage)", int(ideal * 999 // 1000))]:
            data = ("0x38ed1739" + f"{amount_in:064x}" + f"{minout:064x}" + f"{0xa0:064x}"
                    + f"{2:064x}" + pad(WLX) + pad(USDC) + pad(owner) + f"{0:064x}")
            res = call(RTR, data, frm=owner)
            print(f"    swapExactTokensForTokens {label:<32} -> {res[0]}{'' if res[0]=='OK' else ' ' + str(res[1])}")


if __name__ == "__main__":
    main()
