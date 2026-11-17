#!/usr/bin/env bash
# Launch the LXON/USDC pool: the three commands the runbook documents, in order, in one shot.
#
#   bash script/polygon137/LaunchPool137.sh
#
# Why this file exists. `PlanPool137.sh` pins nonces and sets `deadline = chain time + 1 h`. So the gap
# between planning and signing is a hard timeout, and a human retyping a PLAN_DIR into three shells under
# that clock is how a launch ends up broadcasting an edited-by-hand plan or re-planning four times. Nothing
# here is new policy: it calls the same planner, the same signer and the same broadcaster, with the same
# environment, and it refuses before it starts if the pool cannot be funded.
#
# It does NOT sign. Signing still needs the keystore host, and the split is deliberate -- a signature proves
# who signed, not with what, so the launch half never needs to be trusted with anything secret.
#
# Defaults are the owner's 2026-10-29 rulings: 10,000 wLXON + 2,356 native USDC, which sets 1 wLXON =
# $0.2356, LP to the bridge TimelockController. Override any of it, but the planner re-verifies every
# override rather than believing it.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC137="${RPC137:-https://polygon.drpc.org}"
PROVIDER="${PROVIDER:-0x2a8Ca01C53cecF360b181a0B7D49a71565684665}"
WLXON="${WLXON:-0x7A3c0C34f157EfDD3E4913c5224C15E645469093}"
# USDC_KIND, not an address: PlanPool137.sh takes the WORD and resolves the address itself, so passing a
# bare 0x here would die on "USDC= must be native, bridged or full". The address below is derived from the
# kind and is only used for this script's own balance precheck.
USDC_KIND="${USDC_KIND:-native}"
case "$USDC_KIND" in
  native)  USDC_ADDR=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359 ;;
  bridged) USDC_ADDR=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174 ;;
  *)       printf 'FATAL: USDC_KIND must be native or bridged, got %s\n' "$USDC_KIND" >&2; exit 1 ;;
esac
AMOUNT_WLXON="${AMOUNT_WLXON:-10000}"
AMOUNT_USDC="${AMOUNT_USDC:-2356}"
KEYSTORE="${KEYSTORE:-$HOME/.lxon/keystores/polygon-137}"
PASSWORD_FILE="${PASSWORD_FILE:-$HOME/.lxon/secrets/polygon-137.pw}"
PLAN_DIR="${PLAN_DIR:-/tmp/pool137-launch}"
# The self-dealt acknowledgement is the owner's, not a flag a launcher may invent. It is required here
# exactly as it is required by the planner: the split IS the price, and someone has to say they know.
SELFDEALT_ACK="${POOL_SELFDEALT_ACK:-0}"

die(){ printf 'FATAL: %s\n' "$*" >&2; exit 1; }
say(){ printf '  ·    %s\n' "$*"; }
rd(){ local o i; for i in 1 2 3; do o="$(cast call "$@" --rpc-url "$RPC137" 2>/dev/null | head -1 | awk '{print $1}')"
       [ -n "$o" ] && { printf '%s' "$o"; return 0; }; sleep 2; done; printf ''; return 1; }

[ "$SELFDEALT_ACK" = "1" ] || die "this batch sets the visible price of wLXON at $(python3 -c \
  "print('%.6f' % ($AMOUNT_USDC / $AMOUNT_WLXON))" 2>/dev/null) USDC by its own split, with no counterparty \
and no outside bid, and a CoinMarketCap application is open. That acknowledgement is the owner's to give, \
not this script's to assume: re-run with POOL_SELFDEALT_ACK=1."
[ -n "$PLAN_DIR" ] || die "PLAN_DIR must be a new directory"
if [ -s "$PLAN_DIR/plan.json" ]; then
  die "$PLAN_DIR already holds a plan. A plan is single use: its nonces are pinned and its deadline is \
chain time + 1 h. Use a fresh PLAN_DIR (or delete this one deliberately)."
fi
[ -f "$KEYSTORE" ] || die "no keystore at $KEYSTORE -- this runs the launch, not a rehearsal"
[ -f "$PASSWORD_FILE" ] || die "no password file at $PASSWORD_FILE"
[ -z "${PRIVATE_KEY:-}" ] || die "PRIVATE_KEY= is refused: signing reads the keystore, not the environment"

# ---------------------------------------------------------------- the two things the pool is made of
# Checked here because the failure is otherwise discovered three commands deep, after an anvil fork has
# already been started and torn down, and because "0" read through an address I mistyped looks identical
# to "the wallet is empty". Both tokens are confirmed by symbol first.
WS="$(rd "$WLXON" 'symbol()(string)')"; US="$(rd "$USDC_ADDR" 'symbol()(string)')"
[ "$(printf '%s' "$WS" | tr -d '"')" = "wLXON" ] || die "$WLXON reports ${WS:-nothing}, not wLXON"
[ "$(printf '%s' "$US" | tr -d '"')" = "USDC" ] || die "$USDC reports ${US:-nothing}, not USDC -- \
this pool is meant to pair against Circle USDC, not against LXUSD or a project-issued stand-in"
BW="$(rd "$WLXON" 'balanceOf(address)(uint256)' "$PROVIDER")"
BU="$(rd "$USDC_ADDR" 'balanceOf(address)(uint256)' "$PROVIDER")"
# float, not int: the planner itself takes whole-or-fractional tokens (`float(x) * 10**decimals`), and a
# launcher that only accepted integers would refuse 2355.50 USDC while the planner would happily price it.
NEED_W="$(python3 -c "print(int(float('$AMOUNT_WLXON') * 10**18))")"
NEED_U="$(python3 -c "print(int(float('$AMOUNT_USDC') * 10**6))")"
say "provider $PROVIDER holds ${BW:-?} wei wLXON and ${BU:-?} wei USDC"
python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>=int(sys.argv[2]) else 1)" "${BW:-0}" "$NEED_W" \
  || die "the wLXON leg is short: needs $NEED_W wei, holds ${BW:-0}. Fill it with a crossing, not a plan."
python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>=int(sys.argv[2]) else 1)" "${BU:-0}" "$NEED_U" \
  || die "the USDC leg is short: needs $NEED_U wei ($AMOUNT_USDC tokens) and holds ${BU:-0}. Real Circle \
USDC has to be bought and withdrawn to $PROVIDER on Polygon -- it cannot be minted here, and LXUSD is not \
a substitute (its own notice() says 'not USDC, not Circle-issued, not redeemable, not backed by any reserve')."
POL="$(curl -s --max-time 60 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$PROVIDER\",\"latest\"]}" \
  "$RPC137" | python3 -c 'import sys,json;print(int(json.load(sys.stdin).get("result") or "0x0",16))')"
python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>10**15 else 1)" "$POL" \
  || die "provider holds $POL wei POL; three transactions need gas and this would strand a signed plan"
say "gas: $POL wei POL at the provider"
NL="$(curl -s --max-time 60 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionCount\",\"params\":[\"$PROVIDER\",\"latest\"]}" "$RPC137" | python3 -c 'import sys,json;print(int(json.load(sys.stdin)["result"],16))')"
NP="$(curl -s --max-time 60 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionCount\",\"params\":[\"$PROVIDER\",\"pending\"]}" "$RPC137" | python3 -c 'import sys,json;print(int(json.load(sys.stdin)["result"],16))')"
[ "$NL" = "$NP" ] || die "provider has a transaction in flight (latest $NL, pending $NP) -- the plan's three pinned nonces would collide with it"
say "nonce $NL, latest == pending"

# ---------------------------------------------------------------- plan -> sign -> broadcast
printf '\n== 1/3 plan (no key present, gas priced on a fork of the live chain)\n'
AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" PROVIDER="$PROVIDER" WLXON="$WLXON" \
  RPC137="$RPC137" PLAN_DIR="$PLAN_DIR" POOL_SELFDEALT_ACK=1 USDC="$USDC_KIND" \
  bash script/polygon137/PlanPool137.sh || die "the planner refused -- read its message, it is a gate, not noise"
[ -s "$PLAN_DIR/plan.json" ] || die "no plan.json produced"
PRICE="$(python3 -c "import json;print(json.load(open('$PLAN_DIR/plan.json'))['pool']['priceImpliedUsdcPerWlxon'])")"
KIND="$(python3 -c "import json;print(json.load(open('$PLAN_DIR/plan.json'))['pool']['priceKind'][:40])")"
CUST="$(python3 -c "import json;d=json.load(open('$PLAN_DIR/plan.json'));print(d['custody']['kind'],d['custody']['address'])")"
say "planned: 1 wLXON = $PRICE USDC ($KIND) | LP custody: $CUST"

printf '\n== 2/3 sign from the keystore (refuses any key from the environment)\n'
PLAN_DIR="$PLAN_DIR" KEYSTORE="$KEYSTORE" PASSWORD_FILE="$PASSWORD_FILE" \
  bash script/polygon137/SignWlxon137Plan.sh || die "the signer refused -- nothing was broadcast"
N="$(ls -1 "$PLAN_DIR"/signed/*.raw.hex 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" = "3" ] || die "expected 3 signed transactions, found $N"

if [ "${BROADCAST:-0}" != "1" ]; then
  printf '\n== staged, not broadcast. %s holds three signed transactions for a price of %s USDC per wLXON.\n' "$PLAN_DIR/signed" "$PRICE"
  printf '   They are single use and they expire with the plan deadline. To publish:\n'
  printf '     PLAN_DIR="%s" BROADCAST=1 bash script/polygon137/LaunchPool137.sh\n' "$PLAN_DIR"
  printf '   Or from the signed files directly:\n'
  printf '     PLAN_DIR="%s" SIGNED_DIR="%s/signed" bash script/polygon137/BroadcastWlxon137Signed.sh\n' "$PLAN_DIR" "$PLAN_DIR"
  exit 0
fi

printf '\n== 3/3 broadcast (the broadcaster re-derives every signer before it publishes anything)\n'
PLAN_DIR="$PLAN_DIR" SIGNED_DIR="$PLAN_DIR/signed" FORCE=1 RPC137="$RPC137" \
  bash script/polygon137/BroadcastWlxon137Signed.sh || die "the broadcaster refused or failed -- read its output before retrying; a signed transaction that mined without printing is how POL gets burned twice"

printf '\n== the pair now exists? ask the factory, not this script\n'
FACTORY="$(python3 -c "import json;print(json.load(open('$PLAN_DIR/plan.json'))['pool']['factory'])")"
PAIR="$(cast call "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC_ADDR" --rpc-url "$RPC137" 2>/dev/null | head -1)"
printf '   getPair(wLXON, USDC) = %s\n' "$PAIR"
case "$(printf '%s' "$PAIR" | tr 'A-Z' 'a-z')" in
  0x0000000000000000000000000000000000000000) die "the batch reported done but the factory names no pair -- do not announce a pool" ;;
esac
printf '   reserves: %s\n' "$(cast call "$PAIR" 'getReserves()(uint112,uint112,uint32)' --rpc-url "$RPC137" 2>/dev/null | tr '\n' ' ')"
printf '   token0  : %s\n' "$(cast call "$PAIR" 'token0()(address)' --rpc-url "$RPC137" 2>/dev/null | head -1)"
printf '   LP at custody: %s\n' "$(cast call "$PAIR" 'balanceOf(address)(uint256)' "$(printf '%s' "$CUST" | awk '{print $2}')" --rpc-url "$RPC137" 2>/dev/null | head -1)"
printf '\nRecord the price as self-dealt wherever it is quoted. Pulling this liquidity is a 48 h\n'
printf 'timelock operation (script/polygon137/RehearsePoolCustody137.sh proves the exit).\n'
