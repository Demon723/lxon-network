#!/usr/bin/env bash
# Plan a native <-> bridged USDC swap on QuickSwap V2 (Polygon 137), written as a plan.json that the
# existing 137 signer and broadcaster take unchanged.
#
#   TARGET=2356 PLAN_DIR=/tmp/usdcswap bash script/polygon137/PlanUsdcSwap137.sh
#   DIRECTION=bridged-to-native ... | PROVIDER=0x...
#
# It never signs and never broadcasts. Why this exists at all: the pool ruling says the quote asset is
# the *bridged* USDC (`0x2791Bca1…`), but every centralised exchange now withdraws the Circle PoS
# *native* token (`0x3c499c54…`). An owner who funds 2,356 native USDC therefore arrives with the wrong
# token for the plan, and the planner refuses on "provider holds 0 wei of USDC". Swapping one for the
# other is a single approve plus swapExactTokensForTokens on the pair that holds ~5.9M of each, so this
# file turns that step into the same plan -> sign -> broadcast ceremony everything else here uses.
#
# ---------------------------------------------------------------- the checks, and why each one is here
# * The input is computed FROM the pair's live reserves so the output lands on TARGET, not from a
#   remembered exchange rate. QuickSwap V2 takes 0.25 %, so amountIn = resIn*target*1000/((resOut-target)*997).
#   Asking for a fixed 2,356 in and being surprised by 2,349 out is exactly the shortfall this exists to
#   prevent, and it is a 0.3 % error that would have been discovered after the money had already moved.
# * The implied rate is required to sit within RATE_MAX_BPS of 1.0. These two tokens are the same money
#   on two contracts; if the venue ever prices them 1 % apart, something is wrong with the venue or with
#   one of the tokens, and swapping into it under a launch deadline is the worst possible time to find out.
# * Both tokens are re-identified by symbol and decimals on the endpoint being used. This project has
#   already been burned once by a decimal mismatch inside an 18-decimal token.
# * Gas is priced by mining both steps on an anvil fork of the live chain and reading the receipts, never
#   from eth_estimateGas.
# * The provider must hold the input, and the deadline is chain time + 1 h so a stale plan reverts.
# * If the provider already holds TARGET of the destination token, this refuses: swapping what you
#   already have buys nothing and pays 0.25 % for the privilege.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
PLAN_LIB="script/polygon137/lib/plan137.py"

die(){ printf 'FATAL: %s\n' "$*" >&2; exit 1; }
say(){ printf '  ·    %s\n' "$*"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
one(){ printf '%s\n' "$1" | awk 'NR==1{print $1}'; }
num(){ printf '%s\n' "$1" | awk 'NR==1{print $1}' | tr -cd '0-9'; }
j(){ curl -s --max-time 90 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
rpc(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}"; }
result(){ rpc "$1" "$2" "$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result") or "")' 2>/dev/null; }
jp(){ printf '["%s","%s"]' "$1" "$2"; }
code_len(){ local r; r="$(result "$1" eth_getCode "$(jp "$2" latest)" 2>/dev/null)"
  [ -n "$r" ] && printf '%s' "$r" | awk '{print int(length($0)/2)-1}' || printf '0'; }
rd(){ local ep="$1"; shift; local out i
  for i in 1 2 3; do
    out="$(cast call "$1" "$2" "${@:3}" --rpc-url "$ep" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 2
  done; printf '\n'; return 1; }

RPC137="${RPC137:-https://polygon.drpc.org}"
PROVIDER="${PROVIDER:-0x2a8Ca01C53cecF360b181a0B7D49a71565684665}"
NATIVE=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
BRIDGED=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
DIRECTION="${DIRECTION:-native-to-bridged}"
TARGET="${TARGET:-2356}"                       # whole destination tokens wanted
RATE_MAX_BPS="${RATE_MAX_BPS:-50}"             # 0.5 %: these are the same money, so anything wider is a red flag
SLIPPAGE_BPS="${SLIPPAGE_BPS:-0}"              # on amountOutMin, separate from the rate sanity check
SWAP_FEE_BPS="${SWAP_FEE_BPS:-25}"             # QuickSwap V2 takes 0.25 %
PLAN_DIR="${PLAN_DIR:-}"
SWAP_PORT="${SWAP_FORK_PORT:-18981}"
FORK="http://127.0.0.1:$SWAP_PORT"

[ -n "$PLAN_DIR" ] || die "usage: TARGET=<tokens> PLAN_DIR=<new dir> bash script/polygon137/PlanUsdcSwap137.sh"
[ -s "$PLAN_DIR/plan.json" ] && die "$PLAN_DIR already holds a plan; nonces are pinned, use a fresh directory"
mkdir -p "$PLAN_DIR" || die "cannot create $PLAN_DIR"
[ -z "${PRIVATE_KEY:-}" ] || die "PRIVATE_KEY= is refused: this script plans, it must never need a key"

case "$DIRECTION" in
  native-to-bridged) TOK_IN="$NATIVE"; TOK_OUT="$BRIDGED" ;;
  bridged-to-native) TOK_IN="$BRIDGED"; TOK_OUT="$NATIVE" ;;
  *) die "DIRECTION must be native-to-bridged or bridged-to-native, got $DIRECTION" ;;
esac

CHAIN="$(python3 -c 'import sys;print(int(sys.argv[1],16))' "$(result "$RPC137" eth_chainId '[]')")"
[ "$CHAIN" = "137" ] || die "$RPC137 answers chain $CHAIN, not 137"
say "chain $CHAIN via $RPC137"

# ---------------------------------------------------------------- both legs, re-identified
for t in "$TOK_IN" "$TOK_OUT"; do
  [ "$(code_len "$RPC137" "$t")" -gt 100 ] || die "$t has no code on $RPC137"
  s="$(one "$(rd "$RPC137" "$t" 'symbol()(string)')")"
  d="$(num "$(rd "$RPC137" "$t" 'decimals()(uint8)')")"
  [ "$(printf '%s' "$s" | tr -d '"')" = "USDC" ] || die "$t calls itself ${s:-nothing}, not USDC"
  [ "$d" = "6" ] || die "$t reports $d decimals, expected 6 -- refusing to size a USDC swap on a wrong unit"
  say "token $t = USDC, $d decimals"
done

PAIR="$(one "$(rd "$RPC137" "$FACTORY" 'getPair(address,address)(address)' "$NATIVE" "$BRIDGED")")"
[ "$(lc "$PAIR")" != "0x0000000000000000000000000000000000000000" ] || die "no native/bridged USDC pair -- there is nothing to swap through"
[ "$(code_len "$RPC137" "$PAIR")" -gt 100 ] || die "the pair $PAIR has no code"
RF="$(one "$(rd "$RPC137" "$ROUTER" 'factory()(address)')")"
[ "$(lc "$RF")" = "$(lc "$FACTORY")" ] || die "router.factory() = $RF, not $FACTORY"
say "venue: router.factory() == factory, pair $PAIR"

AMT_OUT="$(python3 -c 'import sys;print(int(float(sys.argv[1]) * 10**6))' "$TARGET")"
PB_OUT="$(num "$(rd "$RPC137" "$TOK_OUT" 'balanceOf(address)(uint256)' "$PROVIDER")")"
[ "$(python3 -c "import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))" "$PB_OUT" "$AMT_OUT")" = "1" ] \
  && die "provider already holds $PB_OUT wei of the destination token, which covers TARGET=$TARGET -- swapping would pay ${SWAP_FEE_BPS}bp to move what is already there"

# Input sized from the pair itself, with the constant-product plus fee inversion.
RES="$(rd "$RPC137" "$PAIR" 'getReserves()(uint112,uint112,uint32)')"
R0="$(printf '%s\n' "$RES" | awk 'NR==1{print $1}')"
R1="$(printf '%s\n' "$RES" | awk 'NR==2{print $1}')"
T0="$(one "$(rd "$RPC137" "$PAIR" 'token0()(address)')")"
if [ "$(lc "$T0")" = "$(lc "$TOK_IN")" ]; then RES_IN="$R0"; RES_OUT="$R1"; else RES_IN="$R1"; RES_OUT="$R0"; fi
say "pair reserves: in-side $RES_IN, out-side $RES_OUT (token0 $T0)"
[ "$(python3 -c "import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))" "$RES_OUT" "$AMT_OUT")" = "1" ] \
  || die "the out-side reserve is $RES_OUT and we need $AMT_OUT -- a swap that large would be a price move, not a conversion"

# Two values out of one python call, read with awk on separate lines. A `read ... <<EOF` whose body
# is a $( ) is the exact shape bash 3.2 mis-parses far from the cause, and the amounts are wei so the
# comparison must be done in python, not in [ ].
CALC="$(python3 -c 'import sys
res_in, res_out, out, fee_bps = (int(x) for x in sys.argv[1:5])
amt_in = res_in * out * 10000 // ((res_out - out) * (10000 - fee_bps)) + 1
print(amt_in, int(round(abs(1.0 - (out / amt_in)) * 10000)))' "$RES_IN" "$RES_OUT" "$AMT_OUT" "$SWAP_FEE_BPS")"
AMT_IN="$(printf '%s\n' "$CALC" | awk 'NR==1{print $1}')"
RATE_BPS="$(printf '%s\n' "$CALC" | awk 'NR==1{print $2}')"
say "computed input $(python3 -c "print('%.4f' % ($AMT_IN/1e6))") USDC to yield exactly $TARGET out -- implied rate deviation ${RATE_BPS}bp"
[ "$RATE_BPS" -le "$RATE_MAX_BPS" ] || die "the venue prices these two USDC tokens ${RATE_BPS}bp apart, above the $RATE_MAX_BPSbp sanity bound. Same money on two contracts: a wider gap means something is wrong with one of them, and a launch deadline is the worst time to find out what."

MIN_OUT="$(python3 -c 'import sys;print(int(int(sys.argv[1]) * (10000 - int(sys.argv[2])) // 10000))' "$AMT_OUT" "$SLIPPAGE_BPS")"

PB_IN="$(num "$(rd "$RPC137" "$TOK_IN" 'balanceOf(address)(uint256)' "$PROVIDER")")"
[ "$(python3 -c "import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))" "$PB_IN" "$AMT_IN")" = "1" ] \
  || die "provider holds $PB_IN wei of the input token and the swap needs $AMT_IN -- fund it first"
say "provider holds $PB_IN wei of the input token, needs $AMT_IN"

LATEST="$(python3 -c 'import sys;print(int(sys.argv[1],16))' "$(result "$RPC137" eth_getTransactionCount "$(jp "$(lc "$PROVIDER")" latest)")")"
PENDING="$(python3 -c 'import sys;print(int(sys.argv[1],16))' "$(result "$RPC137" eth_getTransactionCount "$(jp "$(lc "$PROVIDER")" pending)")")"
[ "$LATEST" = "$PENDING" ] || die "$PROVIDER has a transaction in flight (latest $LATEST, pending $PENDING) -- the two pinned nonces would collide"

PRIORITY="$(python3 -c 'import sys;print(int(sys.argv[1],16))' "$(result "$RPC137" eth_maxPriorityFeePerGas '[]')")"
BLK="$(rpc "$RPC137" eth_getBlockByNumber '["latest",false]')"
BASE="$(printf '%s' "$BLK" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("result") or {};print(int(d.get("baseFeePerGas","0x1"),16))')"
NOWT="$(printf '%s' "$BLK" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("result") or {};print(int(d.get("timestamp","0x1"),16))')"
DEADLINE="$(python3 -c 'import sys;print(int(sys.argv[1]) + 3600)' "$NOWT")"
MAXFEE="$(python3 -c 'import sys;print(max(1, 2 * (int(sys.argv[1]) + int(sys.argv[2]))))' "$BASE" "$PRIORITY")"
PLAN_STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "fees: base $BASE, tip $PRIORITY, maxFee $MAXFEE; deadline $DEADLINE (chain time + 1h)"

# ---------------------------------------------------------------- price both steps on a fork of the real chain
printf '\n== mine approve + swap on a fork of %s and take the gas from their receipts\n' "$RPC137"
if lsof -iTCP:"$SWAP_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  die "port $SWAP_PORT is already listening -- a leftover anvil would price this swap against someone else's state and clock"
fi
anvil --fork-url "$RPC137" --chain-id 137 --port "$SWAP_PORT" --auto-impersonate >"$PLAN_DIR/anvil.log" 2>&1 &
SW=$!
cleanup(){ kill "$SW" 2>/dev/null || true; wait "$SW" 2>/dev/null || true; }
trap 'cleanup' EXIT
up=0; for _ in $(seq 1 90); do [ "$(result "$FORK" eth_chainId '[]')" = "0x89" ] && { up=1; break; }; sleep 1; done
[ "$up" = "1" ] || { bad="fork did not start"; die "the fork did not answer chainId 0x89 -- see $PLAN_DIR/anvil.log"; }

send_fork(){ cast send --rpc-url "$FORK" --unlocked --from "$1" "$2" "$3" "${@:4}" 2>&1 | tee "$PLAN_DIR/last-send.log" \
  | awk '$1=="transactionHash"{print $2}' | head -1; }
rfield(){ rpc "$FORK" eth_getTransactionReceipt "[\"$1\"]" | python3 -c 'import sys,json
d=(json.load(sys.stdin).get("result") or {})
k=sys.argv[1]; v=d.get(k)
print(v if k=="status" else (int(v,16) if v else ""))' "$2"; }

# The impersonated provider needs gas on the fork too -- measured the hard way on the pool rehearsal.
j "$FORK" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"anvil_setBalance\",\"params\":[\"$PROVIDER\",\"$(python3 -c 'print(hex(10**20))')\"]}" >/dev/null
AP="$(cast calldata 'approve(address,uint256)' "$ROUTER" "$AMT_IN")"
SW_SIG='swapExactTokensForTokens(uint256,uint256,address[],address,uint256)'
SWP="$(cast calldata "$SW_SIG" "$AMT_IN" "$MIN_OUT" "[$TOK_IN,$TOK_OUT]" "$PROVIDER" "$DEADLINE")"
sel="$(cast sig "$SW_SIG")"
[ "$(printf '%s' "$SWP" | cut -c1-10)" = "$sel" ] || die "swap calldata does not begin with its own selector"

h1="$(send_fork "$PROVIDER" "$TOK_IN" 'approve(address,uint256)' "$ROUTER" "$AMT_IN")"
[ -n "$h1" ] || die "the fork refused the approve: $(head -c 220 "$PLAN_DIR/last-send.log")"
[ "$(rfield "$h1" status)" = "0x1" ] || die "the approve reverted on the fork"
G1="$(rfield "$h1" gasUsed)"
h2="$(send_fork "$PROVIDER" "$ROUTER" "$SW_SIG" "$AMT_IN" "$MIN_OUT" "[$TOK_IN,$TOK_OUT]" "$PROVIDER" "$DEADLINE")"
[ -n "$h2" ] || die "the fork refused the swap: $(head -c 300 "$PLAN_DIR/last-send.log")"
[ "$(rfield "$h2" status)" = "0x1" ] || die "the swap reverted on the fork, so the live pair would too: $(head -c 300 "$PLAN_DIR/last-send.log")"
G2="$(rfield "$h2" gasUsed)"

# External anchor: ask the TOKENS what the provider actually ended up with, rather than restating inputs.
GOT_OUT="$(num "$(cast call "$TOK_OUT" 'balanceOf(address)(uint256)' "$PROVIDER" --rpc-url "$FORK" 2>/dev/null | head -1)")"
LEFT_IN="$(num "$(cast call "$TOK_IN" 'balanceOf(address)(uint256)' "$PROVIDER" --rpc-url "$FORK" 2>/dev/null | head -1)")"
[ "$(python3 -c "import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))" "$GOT_OUT" "$MIN_OUT")" = "1" ] \
  || die "the fork delivered $GOT_OUT, below the minimum $MIN_OUT -- the sizing is wrong, not the node"
[ "$(python3 -c "import sys;print(int(int(sys.argv[1]) == int(sys.argv[2])))" "$GOT_OUT" "$AMT_OUT")" = "1" ] \
  || die "the fork delivered $GOT_OUT and the plan wants exactly $AMT_OUT -- the inversion of the constant product is off by $(python3 -c "print(int(sys.argv[1])-int(sys.argv[2]))" "$GOT_OUT" "$AMT_OUT") wei"
say "fork outcome: provider now holds $GOT_OUT of the destination token (== target) and $LEFT_IN of the input"
cleanup; trap - EXIT

bump(){ python3 -c 'import sys;print(int(int(sys.argv[1]) * 115 // 100) + 1)' "$1"; }
python3 "$PLAN_LIB" add "approve-usdc-in" "$LATEST" "$(lc "$TOK_IN")" 0 "$AP" "$(bump "$G1")" "$MAXFEE" "$PRIORITY" \
  137 "$PROVIDER" "fork gasUsed $G1 x1.15" "hand the router $AMT_IN wei so it can take the input leg"
python3 "$PLAN_LIB" add "swap-usdc" "$((LATEST + 1))" "$(lc "$ROUTER")" 0 "$SWP" "$(bump "$G2")" "$MAXFEE" "$PRIORITY" \
  137 "$PROVIDER" "fork gasUsed $G2 x1.15" "convert $AMT_IN wei $DIRECTION-in to $AMT_OUT wei out, LP to $PROVIDER"

PLAN_START_NONCE="$LATEST" PLAN_CHAIN_ID=137 PLAN_DEPLOYER="$PROVIDER" PLAN_RPC="$RPC137" \
PLAN_MAX_FEE="$MAXFEE" PLAN_PRIORITY_FEE="$PRIORITY" PLAN_PHASE="usdc-swap-$DIRECTION" PLAN_STAMP="$PLAN_STAMP" \
PLAN_FEE_SOURCE="2x live base+tip" PLAN_CAPS_SOURCE="mined on an anvil fork of Polygon 137" \
PLAN_LEGACY_ADDR="$TOK_OUT" PLAN_PREDICTED_WLXON="$TOK_IN" \
  python3 "$PLAN_LIB" finish | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  plan.json: %s (%d tx, nonce %d)" % (d["plan"],d["transactions"],d["startNonce"]))'

python3 - "$PLAN_DIR/plan.json" <<PY
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["swap"] = {
    "venue": "QuickSwap V2 native/bridged USDC pair", "pair": "$PAIR", "router": "$ROUTER",
    "direction": "$DIRECTION", "tokenIn": "$TOK_IN", "tokenOut": "$TOK_OUT",
    "amountInWei": $AMT_IN, "amountOutWei": $AMT_OUT, "amountOutMin": $MIN_OUT,
    "rateDeviationBps": $RATE_BPS, "rateSanityBoundBps": $RATE_MAX_BPS,
    "swapFeeBps": $SWAP_FEE_BPS, "slippageBps": $SLIPPAGE_BPS, "deadline": $DEADLINE,
    "forkAmountOutWei": $GOT_OUT,
    "why": "CEX withdrawals arrive as Circle PoS native USDC; the pool ruling pairs against the legacy "
           "bridged token. Same money, two contracts, ~5.9M deep on both sides of this pair.",
}
json.dump(d, open(p, "w"), indent=1)
print("  annotated: %s -> %s (rate deviation %s bp, fork delivered %s)" % ("$DIRECTION", "$TARGET", "$RATE_BPS", "$GOT_OUT"))
PY

printf '\n== planned. Nothing was signed and nothing was broadcast.\n'
printf '   provider %s\n' "$PROVIDER"
printf '   %s -> %s: in %s wei, out %s wei (%s tokens)\n' "$DIRECTION" "$TARGET" "$AMT_IN" "$AMT_OUT" "$TARGET"
printf '   next:  PLAN_DIR="%s" KEYSTORE=... PASSWORD_FILE=... bash script/polygon137/SignWlxon137Plan.sh\n' "$PLAN_DIR"
printf '   then:  PLAN_DIR="%s" SIGNED_DIR="%s/signed" bash script/polygon137/BroadcastWlxon137Signed.sh\n' "$PLAN_DIR" "$PLAN_DIR"
