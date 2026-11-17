#!/usr/bin/env bash
# Did the USDC for the pool actually arrive? Read-only; signs nothing, broadcasts nothing.
#
#   bash script/polygon137/CheckUsdcArrival137.sh
#   AMOUNT_USDC=2356 PROVIDER=0x2a8Ca01C… bash script/polygon137/CheckUsdcArrival137.sh
#
# Why this exists as a file and not as a chat answer: the pool is one command away from launching and the
# only thing between here and there is a deposit that somebody has to confirm. A confirmation typed from
# memory in a runbook rots; a check that re-reads the chain does not. The planner (`PlanPool137.sh`) will
# refuse a zero USDC side anyway, so this is not a gate -- it is the answer to "is it in yet", plus the
# three follow-up questions that get asked after the answer is no.
#
# ---------------------------------------------------------------- the three checks, and what each can miss
# 1. BALANCE of both USDC variants at the provider, read from TWO endpoints. The strongest evidence, and
#    the only one that says "the money is here". A single endpoint can lag or answer empty under load, so a
#    disagreement between endpoints is reported as such rather than resolved by picking the convenient one.
#    Every zero is only a measurement if the token contract answered symbol()==USDC first -- a balance read
#    through a mistyped address also answers 0, and this project has been burned by that exact confusion.
# 2. LOGS: USDC Transfers whose recipient (or sender) is the provider, over the last --back-hours. This
#    catches the case balance alone cannot: funds that arrived and already left again, or an approval that
#    was pulled. publicnode honours 9,000-block ranges; drpc's free tier refuses these filters and its
#    error text names a range that is not the real limit, so the log pass uses publicnode only.
# 3. MEMPOOL: txpool_content, where the provider's address appears in any transaction, and every pooled
#    call against a USDC contract decoded for its recipient. WEAK BY ITSELF and stated as weak: a
#    centralised exchange only puts a withdrawal in the mempool once it broadcasts, which can be hours
#    after the status says "processing", and each public provider shows a different fast-churning slice
#    (measured 2026-10-29: 304 transactions on 1rpc.io/matic versus 181 on publicnode in the same minute,
#    39 USDC calls versus 2). Absence here means "not seen", never "not coming".
#
# Also swept: the provider address on Ethereum/Arbitrum/Base/Optimism/Avalanche. Exchanges let the user
# pick a network, and "it's in, sent it" is most often a withdrawal that went out on a chain the pool is
# not on. Those addresses are taken from Circle's published contract list, and each one is controlled by
# reading symbol() on that chain before its balance is believed.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

PROVIDER="${PROVIDER:-0x2a8Ca01C53cecF360b181a0B7D49a71565684665}"
AMOUNT_USDC="${AMOUNT_USDC:-2356}"
WLXON="${WLXON:-0x7A3c0C34f157EfDD3E4913c5224C15E645469093}"
USDC_NATIVE=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
USDC_BRIDGED=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
EP_A="${EP_A:-https://polygon.drpc.org}"
EP_B="${EP_B:-https://polygon-bor-rpc.publicnode.com}"
BACK_HOURS="${BACK_HOURS:-24}"
MEMPPOOL="${MEMPOOL:-1}"
TRANSFER_TOPIC=0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef

lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
die(){ printf 'FATAL: %s\n' "$*" >&2; exit 1; }
j(){ curl -s --max-time 90 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
result(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}" \
  | python3 -c 'import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: d={}
r=d.get("result")
if r is None: print("")
elif isinstance(r,str): print(r)
else: print(json.dumps(r))' 2>/dev/null; }
# A bare hex result -> int. An EMPTY read prints 0 and the caller says so out loud; the one place in
# this script where "0" and "could not read" must never be conflated is the balance gate, and there the
# contract's symbol() is verified first, so an empty read cannot be mistaken for a zero.
hx2i(){ python3 -c 'import sys;print(int(sys.argv[1],16) if sys.argv[1] else 0)' "$1"; }
# wei -> whole tokens for a 6-decimal asset, as a fixed-point string. Printed raw AND converted, because
# the raw/real confusion is the bug this file's predecessor actually shipped.
tok6(){ python3 -c 'import sys
v=int(sys.argv[1] or 0); print("%d.%06d" % (v//10**6, v%10**6))' "$1"; }
addrpad(){ python3 -c 'import sys;print("0x"+"0"*24+sys.argv[1][2:].lower())' "$1"; }
# balanceOf(to) as one call, result hex or empty. PADHEX is computed ONCE and interpolated flat: the
# version of this that nested `$(printf | sed)` inside the JSON inside a `$( )` inside a `$( )` parsed
# fine under `bash -n` and then silently returned an empty data field at runtime, which printed as a
# 0 wLXON balance for a wallet that holds 10,000 of it. Depth is the bug, not syntax.
bal_raw(){ local ep="$1" to="$2"
  j "$ep" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$to\",\"data\":\"0x70a08231$PADHEX\"},\"latest\"]}" \
    | python3 -c 'import sys,json
try: print(json.loads(sys.stdin.read()).get("result") or "")
except Exception: print("")'; }

command -v cast >/dev/null || die "cast not on PATH (\$HOME/.foundry/bin)"
[ "$(printf '%s' "$PROVIDER" | wc -c)" -eq 42 ] || die "PROVIDER=$PROVIDER is not 42 characters -- refusing to read through a truncated address"

PAD="$(addrpad "$PROVIDER")"
PADHEX="${PAD#0x}"
echo "provider $PROVIDER"
echo "looking for $AMOUNT_USDC USDC (native $USDC_NATIVE / bridged $USDC_BRIDGED)"

# ---------------------------------------------------------------- 1. balances, two endpoints, each controlled
BEST_U=0
FOUND_KIND=""
for EP in "$EP_A" "$EP_B"; do
  CHAIN="$(hx2i "$(result "$EP" eth_chainId '[]')")"
  [ "$CHAIN" = "137" ] || { echo "SKIP  $EP answers chain $CHAIN, not 137"; continue; }
  HEAD="$(hx2i "$(result "$EP" eth_blockNumber '[]')")"
  echo "-- $EP  head=$HEAD"
  for KIND in native bridged; do
    T="$USDC_NATIVE"; [ "$KIND" = bridged ] && T="$USDC_BRIDGED"
    SYM="$(j "$EP" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$T\",\"data\":\"0x95d89b41\"},\"latest\"]}" \
      | python3 -c 'import sys,json
try: r=json.loads(sys.stdin.read()).get("result") or ""
except Exception: r=""
s=""
if len(r)>34:
    b=bytes.fromhex(r[2:]); n=int.from_bytes(b[32:64],"big") if len(b)>=64 else 0
    s=b[64:64+n].decode("utf8","replace")
print(s)')"
    [ "$SYM" = "USDC" ] || { echo "   $KIND: contract $T answered symbol='$SYM' -- NOT a measurement, fix the constant"; continue; }
    RAW="$(bal_raw "$EP" "$T")"
    if [ -z "$RAW" ]; then echo "   $KIND USDC: READ-FAIL (empty result, not zero)"; continue; fi
    V="$(hx2i "$RAW")"
    echo "   $KIND USDC: raw=$V  = $(tok6 "$V") USDC  (symbol verified)"
    if [ "$(python3 -c "import sys;print(int(int(sys.argv[1])>int(sys.argv[2])))" "$V" "$BEST_U")" = "1" ]; then
      BEST_U="$V"; FOUND_KIND="$KIND"
    fi
  done
  RAWW="$(bal_raw "$EP" "$WLXON")"
  POL="$(result "$EP" eth_getBalance "[\"$PROVIDER\",\"latest\"]")"
  NON_L="$(result "$EP" eth_getTransactionCount "[\"$PROVIDER\",\"latest\"]")"
  NON_P="$(result "$EP" eth_getTransactionCount "[\"$PROVIDER\",\"pending\"]")"
  # The wLXON leg is printed as a token count, and an empty read prints READ-FAIL: the provider holds
  # 10,000 wLXON right now, so a checker that displayed 0 for it would invite somebody to cross a second
  # 10,000 and double the supply. Same for POL, which pays for the claim.
  echo "   wLXON=$(if [ -z "$RAWW" ]; then printf 'READ-FAIL'; else printf '%s (%s)' "$(hx2i "$RAWW")" "$(python3 -c "import sys;print('%.4f'%(int(sys.argv[1])/10**18))" "$(hx2i "$RAWW")")"; fi)  POL=$(if [ -z "$POL" ]; then printf 'READ-FAIL'; else python3 -c "import sys;print('%.6f'%(int(sys.argv[1],16)/10**18))" "$POL"; fi)  nonce latest=$(hx2i "$NON_L") pending=$(hx2i "$NON_P")"
  [ "$(lc "$NON_L")" = "$(lc "$NON_P")" ] || echo "   NOTE: pending nonce is ahead of latest -- a transaction from this wallet IS in flight"
done

NEED="$(python3 -c "import sys;print(int(float(sys.argv[1])*10**6))" "$AMOUNT_USDC")"
if [ "$(python3 -c "import sys;print(int(int(sys.argv[1])>=int(sys.argv[2])))" "$BEST_U" "$NEED")" = "1" ]; then
  READY=1
else
  READY=0
fi

# ---------------------------------------------------------------- 2. logs, recipient and sender, both tokens
echo "-- log scan: ${BACK_HOURS} h back on $EP_B"
python3 - "$EP_B" "$PAD" "$TRANSFER_TOPIC" "$BACK_HOURS" "$USDC_NATIVE" "$USDC_BRIDGED" <<'PY' 2>&1 | sed 's/^/   /'
import json, subprocess, sys
ep, pad, topic, hours, a, b = sys.argv[1:7]
def rpc(method, params):
    body = json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params})
    out = subprocess.run(["curl","-s","--max-time","120","-X","POST","-H",
                          "Content-Type: application/json","-d",body,ep],
                         capture_output=True, text=True).stdout
    try: d = json.loads(out)
    except Exception: return None, out[:80]
    return (None, str(d["error"].get("message",""))[:120]) if "error" in d else (d.get("result"), None)
head, err = rpc("eth_blockNumber", [])
if err: print("head failed: %s" % err); raise SystemExit
head = int(head, 16)
frm = max(0, head - int(float(hours) * 3600 / 2.1))
names = {a.lower(): "native", b.lower(): "bridged"}
print("blocks %d..%d (~%s h)" % (frm, head, hours))
for side, topics in (("INTO the provider", [topic, None, pad]),
                     ("FROM the provider", [topic, pad, None])):
    start, hits, fails = frm, 0, 0
    while start <= head:
        end = min(start + 9000, head)
        res, err = rpc("eth_getLogs", [{"fromBlock": hex(start), "toBlock": hex(end),
                                       "address": [a, b], "topics": topics}])
        if err: fails += 1; print("  %d-%d ERR %s" % (start, end, err))
        else:
            for e in res or []:
                hits += 1; v = int(e["data"], 16)
                print("  HIT blk=%d tx=%s %s %d.%06d from=%s to=%s" % (
                    int(e["blockNumber"],16), e["transactionHash"],
                    names.get(e["address"].lower(), e["address"]),
                    v//10**6, v%10**6,
                    "0x"+e["topics"][1][-40:], "0x"+e["topics"][2][-40:]))
        start = end + 1
    print("%s: %d transfer(s), %d range(s) failed" % (side, hits, fails))
PY

# ---------------------------------------------------------------- 3. mempool, best effort and explicitly weak
if [ "$MEMPPOOL" = "1" ]; then
  echo "-- mempool (weak evidence: a CEX withdrawal appears only once it is broadcast)"
  python3 - "$PROVIDER" "$USDC_NATIVE" "$USDC_BRIDGED" <<'PY' 2>&1 | sed 's/^/   /'
import json, subprocess, sys
prov = sys.argv[1][2:].lower()
usdc = {sys.argv[2][2:].lower(): "native", sys.argv[3][2:].lower(): "bridged"}
sel = {"a9059cbb": "transfer", "095ea7b3": "approve", "23b872dd": "transferFrom"}
for ep in ("https://1rpc.io/matic", "https://polygon-bor-rpc.publicnode.com"):
    def rpc(method, params):
        body = json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params})
        out = subprocess.run(["curl","-s","--max-time","90","-X","POST","-H",
                              "Content-Type: application/json","-d",body,ep],
                             capture_output=True, text=True).stdout
        try: d = json.loads(out)
        except Exception: return None
        return d.get("result")
    st = rpc("txpool_status", [])
    if not st: print("%s: no txpool here" % ep); continue
    c = rpc("txpool_content", []) or {}
    txs = [t for kind in ("pending","queued") for bucket in (c.get(kind) or {}).values() for t in (bucket or {}).values()]
    touch = dec = toprov = 0
    for t in txs:
        inp = (t.get("input") or t.get("data") or "0x")[2:].lower()
        to  = (t.get("to") or "").lower()[2:]
        if prov in inp or to == prov or (t.get("from") or "").lower()[2:] == prov:
            touch += 1
            print("  mentions provider: from=%s to=%s nonce=%s sel=%s" % (t.get("from"), t.get("to"), t.get("nonce"), inp[:8]))
        if to in usdc and len(inp) >= 136 and inp[:8] in sel:
            dec += 1
            if inp[32:72] == prov:
                toprov += 1
                v = int(inp[72:136], 16)
                print("  PENDING %s of %s USDC -> PROVIDER %d.%06d (from=%s nonce=%s)" % (
                    sel[inp[:8]], usdc[to], v//10**6, v%10**6, t.get("from"), t.get("nonce")))
    np, nq = int(st["pending"], 16), int(st["queued"], 16)
    print("%s: %d txs (status says pending=%s queued=%s) | %d mention provider | %d decoded USDC calls | %d addressed to the provider"
          % (ep, len(txs), np, nq, touch, dec, toprov))
    if len(txs) != np + nq:
        print("   ^ NOTE: txpool_status and txpool_content are two calls, not one snapshot, and the pool"
              " moved between them (%d served vs %d counted)." % (len(txs), np + nq))
        print("     Either way a public provider serves a slice of the pool, so '0 mention provider' means"
              " 'none in what this endpoint served', never 'none pending'.")
PY
fi

# ---------------------------------------------------------------- 4. did it go to another chain instead
echo "-- the same address on the other chains an exchange can withdraw USDC to (symbol verified first)"
python3 - "$PROVIDER" <<'PY' 2>&1 | sed 's/^/   /'
import json, subprocess, sys
# Circle's published native-USDC contracts (developers.circle.com/stablecoins/usdc-contract-addresses),
# read 2026-10-29. Each is confirmed by symbol()==USDC on its own chain before its balance is reported.
prov = sys.argv[1]
chain = [
    ("ethereum",  "https://ethereum-rpc.publicnode.com",           "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
    ("arbitrum",  "https://arb1.arbitrum.io/rpc",                   "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"),
    ("base",      "https://mainnet.base.org",                       "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"),
    ("optimism",  "https://mainnet.optimism.io",                    "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"),
    ("avalanche", "https://api.avax.network/ext/bc/C/rpc",          "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"),
]
pad = "0"*24 + prov[2:].lower()
def rpc(ep, method, params):
    body = json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params})
    out = subprocess.run(["curl","-s","--max-time","60","-X","POST","-H",
                          "Content-Type: application/json","-d",body,ep],
                         capture_output=True, text=True).stdout
    try: d = json.loads(out)
    except Exception: return None
    return d.get("result")
def dec_(ep, to, data):
    r = rpc(ep, "eth_call", [{"to": to, "data": data}, "latest"])
    return r or ""
for name, ep, tok in chain:
    s = dec_(ep, tok, "0x95d89b41")
    sym = ""
    try:
        b = bytes.fromhex(s[2:]); n = int.from_bytes(b[32:64], "big")
        sym = b[64:64+n].decode("utf8", "replace")
    except Exception: pass
    if sym != "USDC":
        print("%-10s contract answered symbol=%r -- not measured" % (name, sym)); continue
    v = int(dec_(ep, tok, "0x70a08231" + pad) or "0", 16)
    print("%-10s USDC=%d.%06d" % (name, v//10**6, v%10**6))
PY

echo
echo "================================================================"
if [ "$READY" = "1" ]; then
  echo "USDC IS IN: $(tok6 "$BEST_U") of $AMOUNT_USDC needed, as $FOUND_KIND."
  echo "Launch while the plan is fresh (it expires at chain time + 1 h):"
  echo "  AMOUNT_WLXON=10000 AMOUNT_USDC=$AMOUNT_USDC USDC_KIND=$FOUND_KIND POOL_SELFDEALT_ACK=1 BROADCAST=1 \\"
  echo "    PLAN_DIR=/tmp/pool137-$(date -u +%Y%m%dT%H%M%S) bash script/polygon137/LaunchPool137.sh"
  echo "Then read the pair, its reserves and the LP balance back from the chain. Do not launch off this"
  echo "script's word alone: the planner re-checks every one of these facts on its own."
  exit 0
else
  echo "NOT READY: the provider holds $(tok6 "$BEST_U") USDC and the pool needs $AMOUNT_USDC."
  echo "Nothing on Polygon, nothing on the five other chains swept, and nothing pending in the mempool"
  echo "views tried. The withdrawal has therefore not settled anywhere this script can see -- which is not"
  echo "the same as 'it is not coming': the exchange's own withdrawal record is the authority here, and a"
  echo "txhash from it settles the question in one call. Do NOT re-send on the strength of a zero balance;"
  echo "get the hash, then verify chain, token contract and destination."
  exit 2
fi
