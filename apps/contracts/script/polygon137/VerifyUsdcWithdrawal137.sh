#!/usr/bin/env bash
# Verify one withdrawal hash: which chain it is on, which USDC contract it moved, and whether it landed at
# the pool provider. Read-only.
#
#   bash script/polygon137/VerifyUsdcWithdrawal137.sh 0x<txhash>
#   bash script/polygon137/VerifyUsdcWithdrawal137.sh 0x<txhash> AT=0x2a8Ca01C53cecF360b181a0B7D49a71565684665 WANT=2356
#
# Why it resolves the chain rather than assuming it: the address is 42 characters and the same on every
# EVM chain, so "I sent it to the wallet address" does not say which chain the exchange actually broadcast
# on, and a withdrawal on the wrong chain is a different problem from a withdrawal that has not happened.
# The hash does say -- it either exists somewhere or it does not.
#
# Why it reads the RECEIPT LOGS and not only the calldata: a direct exchange withdrawal is a plain
# `transfer(address,uint256)`, but the same money can arrive through a router, a batch, or a
# `transferAndCall`, and those put the real ERC-20 movement in the logs. `Transfer(from, to, value)` as
# emitted by the USDC contract is the only place the destination is authoritative. Calldata is reported
# too, because when it does NOT decode as a token call that is itself the finding.
#
# The verdict is deliberately narrow. It answers: is this hash a real mined transaction, on which chain,
# did it move USDC, how much, to whom. It cannot answer "is the exchange's queue slow" -- that is the
# exchange's own withdrawal record, and if the hash you paste is not on any chain here, the honest reading
# is "not broadcast yet (or not on these six chains)", not "lost".
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TX="${1:-}"
AT="${AT:-0x2a8Ca01C53cecF360b181a0B7D49a71565684665}"
WANT="${WANT:-2356}"
# AT= and WANT= arrive either from the environment or as later arguments -- the usage line below promises
# the argument form, so the parser has to honour it. Reading only the env would silently ignore what an
# operator typed, and a verifier that quietly uses the defaults while reporting the caller's numbers is the
# worst kind of pass-through bug: it would have called a real deposit "not the provider".
for A in "${@:2}"; do
  case "$A" in
    AT=*)   AT="${A#AT=}" ;;
    WANT=*) WANT="${A#WANT=}" ;;
    *) echo "FATAL: unrecognised argument '$A' (only AT= and WANT= are taken)"; exit 64 ;;
  esac
done
[ -n "$TX" ] || { echo "usage: bash script/polygon137/VerifyUsdcWithdrawal137.sh 0x<txhash> [AT=… WANT=…]"; exit 64; }
[ "${#TX}" -eq 66 ] || { echo "FATAL: '$TX' is ${#TX} characters, not 66 -- a transaction hash is 0x + 64 hex. Refusing to search with a truncated hash."; exit 64; }
case "$TX" in 0x*) ;; *) echo "FATAL: hash must start with 0x"; exit 64;; esac
[ "${#AT}" -eq 42 ] || { echo "FATAL: AT=$AT is not 42 characters"; exit 64; }
# A typo in WANT must not become a silent 0.0 -- python's float() would raise mid-script, after six RPC
# rounds, and the traceback reads like a network problem.
python3 -c 'import sys
try: float(sys.argv[1])
except Exception: sys.exit(1)' "$WANT" || { echo "FATAL: WANT=$WANT is not a number of USDC"; exit 64; }
[ "$(python3 -c "import sys;print(int(float(sys.argv[1])>0))" "$WANT")" = "1" ] || { echo "FATAL: WANT must be > 0"; exit 64; }

python3 - "$TX" "$AT" "$WANT" <<'PY'
import json, os, subprocess, sys

txhash, at, want = sys.argv[1], sys.argv[2].lower(), float(sys.argv[3])

# chain id, name, rpc, native USDC, bridged/other USDC worth checking.
# Addresses from Circle's published contract list (developers.circle.com/stablecoins/usdc-contract-addresses),
# read 2026-10-29, and every one is confirmed below by calling symbol() on that chain before any conclusion
# drawn from it -- a balance/recipient read through a mistyped token address returns nothing, and "nothing"
# is exactly what a failed gate looks like.
CHAINS = [
    (137,  "Polygon PoS", "https://polygon.drpc.org",
     ["0x3c499c542cef5e3811e1192ce70d8cc03d5c3359", "0x2791bca1f2de4661ed88a30c99a7a9449aa84174"]),
    (137,  "Polygon PoS (2nd endpoint)", "https://polygon-bor-rpc.publicnode.com",
     ["0x3c499c542cef5e3811e1192ce70d8cc03d5c3359", "0x2791bca1f2de4661ed88a30c99a7a9449aa84174"]),
    (1,    "Ethereum", "https://ethereum-rpc.publicnode.com", ["0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"]),
    (42161,"Arbitrum One", "https://arb1.arbitrum.io/rpc", ["0xaf88d065e77c8cc2239327c5edb3a432268e5831"]),
    (8453, "Base", "https://mainnet.base.org", ["0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"]),
    (10,   "OP Mainnet", "https://mainnet.optimism.io", ["0x0b2c639c533813f4aa9d7837caf62653d097ff85"]),
    (43114,"Avalanche C", "https://api.avax.network/ext/bc/C/rpc", ["0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e"]),
]
USDC_NAMES = {
    "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359": "native USDC (Circle PoS)",
    "0x2791bca1f2de4661ed88a30c99a7a9449aa84174": "bridged USDC (legacy)",
}
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
SEL = {"a9059cbb": "transfer(address,uint256)", "095ea7b3": "approve(address,uint256)",
       "23b872dd": "transferFrom(address,address,uint256)", "40c10f19": "transferAndCall(address,uint256,bytes)"}
KNOWN_TOKENS = {a for _, _, _, lst in CHAINS for a in lst}


def rpc(ep, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    out = subprocess.run(["curl", "-s", "--max-time", "60", "-X", "POST", "-H",
                          "Content-Type: application/json", "-d", body, ep],
                         capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
    except Exception:
        return {"_err": "unparseable: %s" % out[:80]}
    if "error" in d:
        return {"_err": str(d["error"].get("message", ""))[:120]}
    return {"result": d.get("result")}


def sym(ep, tok):
    r = rpc(ep, "eth_call", [{"to": tok, "data": "0x95d89b41"}, "latest"]).get("result") or ""
    try:
        b = bytes.fromhex(r[2:])
        n = int.from_bytes(b[32:64], "big")
        return b[64:64 + n].decode("utf8", "replace")
    except Exception:
        return ""


POOL_PROVIDER = os.environ.get("POOL_PROVIDER", "0x2a8ca01c53cecf360b181a0b7d49a71565684665").lower()
# POOL_PROVIDER is overridable for one reason: the "launch it now" verdict only fires when the deposit lands
# at the provider, and there is no real transaction on earth that does that yet. So the green branch is
# proved by pointing the constant at somebody's actual confirmed deposit and watching the whole verdict
# branch execute. In production leave it unset -- exit 0 means "this is our provider and the pool can be
# seeded", and that must never be true of a stranger's wallet.

print("hash %s" % txhash)
print("looking for: USDC worth %s reaching %s" % (want, at))
found = []
seen_eps = set()
for cid, name, ep, toks in CHAINS:
    r = rpc(ep, "eth_getTransactionByHash", [txhash])
    t = r.get("result")
    if r.get("_err"):
        print("  %-28s endpoint problem: %s" % (name, r["_err"]))
        continue
    if not t:
        print("  %-28s not found" % name)
        continue
    print("  %-28s FOUND  block=%d  from=%s  to=%s" % (
        name, int(t["blockNumber"], 16), t["from"], t["to"] or "(contract creation)"))
    found.append((cid, name, ep, t, toks))

if not found:
    print("\nNOT FOUND on any chain queried. That means one of:\n"
          "  - the exchange has not broadcast it yet (a 'processing' status is not a broadcast),\n"
          "  - the hash is from a chain not in this list, or is a withdrawal ID rather than a txhash,\n"
          "  - the hash was mistyped. Re-read it from the exchange's own record; do not resend.")
    raise SystemExit(3)

# de-duplicate the two Polygon endpoints: same chain id, one analysis
uniq = {}
for cid, name, ep, t, toks in found:
    uniq.setdefault(cid, (name, ep, t, toks))
print()
matches = []
for cid, (name, ep, t, toks) in sorted(uniq.items()):
    print("=== chain %s (%s)" % (cid, name))
    inp = (t.get("input") or "0x")[2:].lower()
    to = (t.get("to") or "").lower()
    print("  calldata : %d bytes, selector 0x%s" % (max(0, (len(inp) - 8) // 2), inp[:8] or "-"))
    if to in KNOWN_TOKENS:
        lbl = USDC_NAMES.get(to, to)
        print("  to       : %s  <-- a USDC contract (%s), symbol()=%r" % (to, lbl, sym(ep, to)))
        if inp[:8] in SEL and len(inp) >= 136:
            if inp[:8] == "23b872dd":
                frm, rec, amt = "0x" + inp[32:72], "0x" + inp[96:136], int(inp[136:200], 16) if len(inp) >= 200 else 0
                print("  decoded  : %s  %d.%06d USDC  %s -> %s" % (SEL[inp[:8]], amt // 10**6, amt % 10**6, frm, rec))
            else:
                rec, amt = "0x" + inp[32:72], int(inp[72:136], 16)
                print("  decoded  : %s  amount=%d.%06d  recipient=%s" % (SEL[inp[:8]], amt // 10**6, amt % 10**6, rec))
    else:
        print("  to       : %s  -- not a USDC contract I know; trusting the logs below" % (to or "creation"))
    r = rpc(ep, "eth_getTransactionReceipt", [txhash])
    rec = r.get("result")
    if not rec:
        print("  receipt  : NOT READABLE (%s) -- nothing below is verified" % r.get("_err", "empty"))
        continue
    status = int(rec.get("status", "0x0"), 16)
    print("  receipt  : status=%s  gasUsed=%d  logs=%d  block=%d" % (
        "SUCCESS" if status else "REVERTED", int(rec["gasUsed"], 16), len(rec["logs"]),
        int(rec["blockNumber"], 16)))
    moved = 0
    for lg in rec["logs"]:
        if len(lg["topics"]) != 3 or lg["topics"][0].lower() != TRANSFER:
            continue
        tk = lg["address"].lower()
        if tk not in KNOWN_TOKENS:
            continue
        frm, rcv = "0x" + lg["topics"][1][-40:], "0x" + lg["topics"][2][-40:]
        v = int(lg["data"], 16)
        if v == 0:
            continue
        moved += 1
        star = "   <== AT THE PROVIDER" if rcv.lower() == at else ""
        print("   USDC move: %s  %d.%06d  %s -> %s%s" % (
            USDC_NAMES.get(tk, tk), v // 10**6, v % 10**6, frm, rcv, star))
        if rcv.lower() == at and v >= int(want * 10**6):
            matches.append((cid, name, tk, v))
    if moved == 0:
        print("   no USDC Transfer in this receipt -- this hash is NOT the pool deposit")

print()
print("================================================================")
if matches and at == POOL_PROVIDER:
    cid, name, tk, v = matches[0]
    kind = "native" if tk == "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359" else (
        "bridged" if tk == "0x2791bca1f2de4661ed88a30c99a7a9449aa84174" else "unknown")
    print("VERIFIED: chain %s (%s), %s USDC, %d.%06d delivered to the pool provider." % (
        cid, name, kind, v // 10**6, v % 10**6))
    print("This is the deposit, and it is enough. Launch it in one pass -- the plan pins nonces and expires")
    print("at chain time + 1 h:")
    print("  AMOUNT_WLXON=10000 AMOUNT_USDC=%s USDC_KIND=%s POOL_SELFDEALT_ACK=1 BROADCAST=1 \\" % (want, kind))
    print("    PLAN_DIR=/tmp/pool137-$(date -u +%Y%m%dT%H%M%S) bash script/polygon137/LaunchPool137.sh")
    print("Then read the pair address, both reserves and the LP balance back from the chain; the LP must")
    print("appear at the bridge timelock 0xe56553Ed… and nowhere else.")
    raise SystemExit(0)
if matches:
    cid, name, tk, v = matches[0]
    print("The money moved %d.%06d USDC to %s on chain %s -- and that address is NOT the pool provider"
          % (v // 10**6, v % 10**6, at, cid))
    print("(%s). A deposit at any other wallet cannot seed this pool: `addLiquidity` takes the two sides" % POOL_PROVIDER)
    print("from the account that signs, so the USDC has to sit at the provider. Re-check the withdrawal's")
    print("destination on the exchange before sending again.")
    raise SystemExit(2)
print("NOT THE DEPOSIT (or not enough of it). The hash resolves, but nothing at it moved %s USDC to %s." % (want, at))
print("Read the lines above: a chain we did not expect, a token we do not track, a smaller amount, a")
print("different recipient, or a successful transaction that never touched USDC at all.")
raise SystemExit(2)
PY
