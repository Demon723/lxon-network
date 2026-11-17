#!/usr/bin/env bash
# Plan a wLXON/USDC liquidity pool on QuickSwap V2 (Polygon 137): approve both tokens, then
# addLiquidity -- written as a plan.json the existing 137 signer and broadcaster take unchanged.
#
#   AMOUNT_WLXON=500 AMOUNT_USDC=120 PLAN_DIR=/tmp/pool137 \
#     POOL_SELFDEALT_ACK=1 bash script/polygon137/PlanPool137.sh
#
# It never signs and never broadcasts. `SignWlxon137Plan.sh` signs on the keystore host;
# `BroadcastWlxon137Signed.sh` publishes after re-deriving every signature. Same split as every other
# ceremony here, for the same reason: a signature proves who signed, not with what.
#
# ---------------------------------------------------------------- read this before you run it
# A pool is not a price. `addLiquidity` at whatever split this script is handed *becomes* the visible
# market price of wLXON, because there is no other venue and no outside buyer. Measured 2026-10-28:
#   * the pair does not exist yet -- `factory.getPair(wLXON, USDC) = 0x0`,
#   * the entire supply of new wLXON on Polygon is 1,000 tokens, all of it in the founder `0x7F715B7F…`,
#     and that wallet holds 0 POL so it cannot even approve,
#   * no project wallet holds any USDC at all -- 0 measured for both USDC variants across the 137
#     deployer, the founder, the legacy holder, the 724 validator key and the migration contract.
# The repo's own deployment notes already name this failure mode ("how a self-issued asset gets a
# fictional market cap"), so this planner does three things instead of one: it refuses when either side
# is zero; it writes the implied price into plan.json labelled SELF-DEALT; and it will not proceed
# without POOL_SELFDEALT_ACK=1, because that number is what anyone quoting wLXON -- including the open
# CoinMarketCap application -- will read, and a thin pool is movable by whoever holds the LP.
#
# USDC is 6 decimals and wLXON is 18. Both are read from the contracts at plan time, never assumed: this
# project has already been burned once by a decimals mismatch inside an 18-decimal token.
#
# The deadline is chain time + 1 h, so a plan that sits unsigned for more than an hour reverts by
# design. Re-plan; do not edit the deadline by hand.
#
# ---------------------------------------------------------------- LP custody (owner ruling 2026-10-29: timelock)
# `addLiquidity` mints LP to whoever its `to` argument names, and LP is the redeemable position: whoever
# holds it can pull the pool. So custody is a separate decision from seeding it, and the ruling on it is
# "a timelock". The default recipient here is therefore the 137 bridge TimelockController
# `0xe56553Ed…`, chosen over the migration TimelockController `0x5Bfc2fD8…` for one measured reason
# (re-read on 2026-10-29, not recalled):
#
#   0xe56553Ed…  getMinDelay 172800 | DEFAULT_ADMIN = itself | deployer PROPOSER+EXECUTOR+CANCELLER,
#                                       deployer DEFAULT_ADMIN = false
#   0x5Bfc2fD8…  getMinDelay 172800 | DEFAULT_ADMIN = itself AND the deployer -> the hot key can
#                                       `grantRole`/`revokeRole` and change roles instantly, so the 48 h
#                                       is a habit rather than a control there.
#
# The planner will not take either of those on faith: it re-reads `getMinDelay`, `isOperation` and the
# four role facts from the endpoint it is about to plan against, and it refuses a `LP_TO` that has no code
# (an EOA is hot custody, which is a legitimate choice that has to be said out loud with
# LP_TO_HOT_ACK=1) or a timelock whose DEFAULT_ADMIN is held by the same key that proposes and executes
# (LP_TO_WEAK_ACK=1 to accept that anyway, which this session will not set for you).
#
# Locking the LP is not the same as being able to get it out, and a custody route that cannot be unwound
# is a burn. The exit is two timelock calls in one batch -- `pair.approve(router, lp)` then
# `router.removeLiquidity(wLXON, USDC, lp, minA, minB, to, deadline)` -- and
# `RehearsePoolCustody137.sh` proves that whole sequence on a fork of the real chain, including that it
# is refused before the 48 h has passed. Read the measured cost of the exit there, and note its shape:
# pulling liquidity is a two-day operation once the LP is in there. That is the point of the ruling, and
# it is also the thing to know before anyone asks for a quick rebalance.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
PLAN_LIB="script/polygon137/lib/plan137.py"

die(){ printf 'FATAL: %s\n' "$*" >&2; exit 1; }
say(){ printf '  ·    %s\n' "$*"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
stripq(){ printf '%s' "$1" | tr -d '"'; }
j(){ curl -s --max-time 90 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
rpc(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}"; }
# `cast call` prints tuple components one line each, so multi-value reads keep every line and single
# reads take field 1 of line 1. An empty read is retried: public Polygon endpoints answer nothing under
# load, and an empty read looks exactly like a failed gate.
rpc_read(){ local ep="$1"; shift; local out i
  for i in 1 2 3; do
    out="$(cast call "$1" "$2" "${@:3}" --rpc-url "$ep" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 2
  done; printf '\n'; return 1; }
rd(){ rpc_read "$RPC137" "$@"; }
rdf(){ rpc_read "$FORK" "$@"; }
one(){ printf '%s\n' "$1" | awk 'NR==1{print $1}'; }
num(){ printf '%s\n' "$1" | awk 'NR==1{print $1}' | tr -cd '0-9'; }
int16(){ python3 -c 'import sys;print(int(sys.argv[1],16))' "$1"; }
ge(){ python3 -c 'import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))' "$1" "$2"; }
# Comparisons go through python. bash 3.2's `[ n -gt 0 ]` errors on a wei amount -- 500e18 is over
# 2**63 -- and the error text makes the branch look like it answered, which is how a 500-token side read
# as "the wLXON side is zero".
gt(){ python3 -c 'import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))' "$1" "$2"; }
result(){ rpc "$1" "$2" "$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result") or "")' 2>/dev/null; }
# Params are built with printf into a plain variable, never with escaped quotes inside a
# nested $( ). bash 3.2 dies on the latter -- measured here as "unexpected EOF while looking
# for a matching )" reported on the very line that defines the helper, five lines before the
# first thing that uses it, which is a long way from the cause to go looking for a bug.
jp(){ printf '["%s","%s"]' "$1" "$2"; }
code_len(){ local r; r="$(result "$1" eth_getCode "$(jp "$2" latest)" 2>/dev/null)"
  [ -n "$r" ] && printf '%s' "$r" | awk '{print int(length($0)/2)-1}' || printf '0'; }

# drpc by default, not publicnode. This planner mines its three steps on an anvil fork to price them, and
# a fork rooted at polygon-bor-rpc.publicnode.com cannot serve eth_getTransactionReceipt for a transaction
# it just mined -- it answers 403 "Archive requests require a personal token", so the pricing stage dies
# after having already applied the state change. Measured 2026-10-29. polygon.drpc.org carries the history
# an anvil fork needs.
RPC137="${RPC137:-https://polygon.drpc.org}"
PROVIDER="${PROVIDER:-0x2a8Ca01C53cecF360b181a0B7D49a71565684665}"   # supplies both sides, receives the LP
WLXON="${WLXON:-0x7A3c0C34f157EfDD3E4913c5224C15E645469093}"          # the v4.1 bridge-mint-only token
USDC_VARIANT="${USDC:-native}"
# An if-chain, not a case: bash 3.2 will not parse `${VAR:?a message with spaces}` inside a quoted
# case arm -- measured here as "syntax error near unexpected token (" pointing two lines away from the
# cause, the same family of lexer trouble as a quoted $() that begins with a parenthesis.
if [ "$USDC_VARIANT" = "native" ]; then
  USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359           # Circle-issued PoS USDC
elif [ "$USDC_VARIANT" = "bridged" ]; then
  USDC=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174           # the older bridged USDC
elif [ "$USDC_VARIANT" = "full" ]; then
  [ -n "${USDC_ADDR:-}" ] || die "USDC=full requires USDC_ADDR= the token address to use"
  USDC="$USDC_ADDR"
else
  die "USDC= must be native, bridged or full. Got $USDC_VARIANT"
fi
# Verified, not recalled -- every one of these was confirmed on-chain before being written here: the
# factory answers feeTo(), the router's factory() returns this exact factory, the router's WETH() is a
# live contract, and getPair(routerWETH, USDC) names a pair holding 11,293 bytes of code. A wrong
# "known" factory address is how a launch sends approvals to nothing, so the planner re-checks all four
# on the endpoint it is about to use instead of trusting this comment.
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32                   # QuickSwap V2 factory
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff                    # QuickSwap V2 router
AMOUNT_WLXON="${AMOUNT_WLXON:-}"
AMOUNT_USDC="${AMOUNT_USDC:-}"
SLIPPAGE_BPS="${SLIPPAGE_BPS:-0}"                                    # 0 = exact: the plan's price or nothing
# LP custody. Default is the 137 bridge TimelockController; overridable, but every override is verified
# below rather than trusted, and an EOA destination has to be acknowledged as hot custody.
LP_TO_DEFAULT=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5
# The migration TimelockController, named here so the refusal message can point at the address an operator
# is most likely to type by mistake and say why it is the weaker of the two.
LP_TO_WEAK_DEFAULT=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054
LP_TO="${LP_TO:-$LP_TO_DEFAULT}"
# OZ AccessControl role ids, as bytes32. These are keccak of the role names, so they are the same on every
# TimelockController; the script still reads PROPOSER_ROLE from the contract and compares, because a role
# hash typed from a comment is exactly the kind of thing that quietly stops matching the deployed code.
R_ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
R_PROPOSER=0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1
R_EXECUTOR=0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63
R_CANCELLER=0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783
PLAN_FORK_PORT="${PLAN_FORK_PORT:-18999}"
FORK="http://127.0.0.1:$PLAN_FORK_PORT"

PLAN_DIR="${PLAN_DIR:-}"
[ -n "$PLAN_DIR" ] || die "usage: AMOUNT_WLXON=<tokens> AMOUNT_USDC=<usdc> PLAN_DIR=<new dir> POOL_SELFDEALT_ACK=1 bash script/polygon137/PlanPool137.sh"
[ -f "$PLAN_DIR/plan.json" ] && die "$PLAN_DIR already holds a plan; a plan is single use -- its nonces are pinned, so use a new directory."
mkdir -p "$PLAN_DIR" || die "cannot create $PLAN_DIR"
[ -z "${PRIVATE_KEY:-}" ] || die "PRIVATE_KEY= is refused: this script plans, it must never need a key."
[ -n "$AMOUNT_WLXON" ] && [ -n "$AMOUNT_USDC" ] || die "AMOUNT_WLXON and AMOUNT_USDC are both required (whole tokens). Refusing to invent a split."
# JSON params are built here, in plain assignments. bash 3.2 cannot parse a third level of
# command substitution -- one $( ) inside a quoted " $( ) " inside another -- and reports
# unexpected EOF while looking for a matching ) two lines away from the real cause.
PLC="$(lc "$PROVIDER")"
P_LATEST="$(jp "$PLC" latest)"
P_PENDING="$(jp "$PLC" pending)"
PLAN_STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------- the venue, re-verified on this endpoint
CHAIN="$(int16 "$(result "$RPC137" eth_chainId '[]')")"
[ "$CHAIN" = "137" ] || die "$RPC137 answers chain $CHAIN, not 137 -- nothing may be planned against it"
say "chain $CHAIN via $RPC137"
[ "$(code_len "$RPC137" "$FACTORY")" -gt 100 ] || die "the QuickSwap factory $FACTORY has no code on $RPC137"
[ "$(code_len "$RPC137" "$ROUTER")"  -gt 100 ] || die "the QuickSwap router $ROUTER has no code on $RPC137"
RF="$(one "$(rd "$ROUTER" 'factory()(address)')")"
[ "$(lc "$RF")" = "$(lc "$FACTORY")" ] || die "the router names $RF as its factory, not $FACTORY -- the pair would be created where the router cannot route"
RW="$(one "$(rd "$ROUTER" 'WETH()(address)')")"
[ "$(code_len "$RPC137" "$RW")" -gt 100 ] || die "the router's WETH $RW has no code"
REFPAIR="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$RW" "$USDC")")"
[ "$(code_len "$RPC137" "$REFPAIR")" -gt 100 ] \
  || die "getPair(routerWETH, USDC) = $REFPAIR with no code -- this is not the live V2 factory it claims to be"
say "venue confirmed: router.factory()==factory, router.WETH()=$RW, WETH/USDC pair $REFPAIR exists"

# ---------------------------------------------------------------- the tokens, read not assumed
D_W="$(num "$(rd "$WLXON" 'decimals()(uint8)')")"
D_U="$(num "$(rd "$USDC" 'decimals()(uint8)')")"
S_W="$(stripq "$(one "$(rd "$WLXON" 'symbol()(string)')")")"
S_U="$(stripq "$(one "$(rd "$USDC" 'symbol()(string)')")")"
[ -n "$D_W" ] && [ -n "$D_U" ] || die "could not read decimals() from both tokens"
[ "$D_U" = "6" ] || die "$USDC reports $D_U decimals, expected 6 -- refusing to price USDC on an 18-decimal assumption"
[ "$S_U" = "USDC" ] || die "$USDC calls itself '$S_U', not USDC"
[ "$S_W" = "wLXON" ] || die "$WLXON calls itself '$S_W' -- is this the v4.1 payout token?"
SUP_W="$(num "$(rd "$WLXON" 'totalSupply()(uint256)')")"
BRIDGE_W="$(one "$(rd "$WLXON" 'bridge()(address)')")"
say "tokens: $S_W decimals=$D_W supply=$SUP_W (its bridge is $BRIDGE_W)  |  $S_U decimals=$D_U"

AMT_W="$(python3 -c 'import sys;print(int(float(sys.argv[1]) * 10**int(sys.argv[2])))' "$AMOUNT_WLXON" "$D_W")"
AMT_U="$(python3 -c 'import sys;print(int(float(sys.argv[1]) * 10**int(sys.argv[2])))' "$AMOUNT_USDC" "$D_U")"
[ "$(gt "$AMT_W" 0)" = "1" ] || die "the wLXON side is zero"
[ "$(gt "$AMT_U" 0)" = "1" ] || die "the USDC side is zero. A pool with no USDC in it is not a market, it is a placeholder"
[ "$(ge "$SUP_W" "$AMT_W")" = "1" ] || die "the pool would need $AMOUNT_WLXON $S_W and only $SUP_W wei exists in total -- more supply comes from crossing LXON, not from planning a pool"

# ---------------------------------------------------------------- the price, stated before it is set
PRICE="$(python3 -c 'import sys;a=int(sys.argv[1])/10**int(sys.argv[2]);b=int(sys.argv[3])/10**int(sys.argv[4]);print("%.6f" % (a/b))' "$AMT_U" "$D_U" "$AMT_W" "$D_W")"
if [ "${POOL_SELFDEALT_ACK:-0}" != "1" ]; then
  die "this batch SETS the visible price of $S_W at $PRICE $S_U by your own split, with no counterparty and no outside bid. It becomes the number anyone quoting $S_W reads, and the CoinMarketCap application is open. If you accept that it is self-dealt and not a market, re-run with POOL_SELFDEALT_ACK=1"
fi
say "implied price: 1 $S_W = $PRICE $S_U  (from a $AMOUNT_WLXON / $AMOUNT_USDC split -- SELF-DEALT, not a market)"

# ---------------------------------------------------------------- custody: who holds the LP, and can it get out
# Measured here rather than assumed, because the whole value of "timelock custody" is the shape of the
# roles on the destination -- and the two timelocks this project owns differ in exactly that respect.
CUSTODY_KIND=""
C_MIN_DELAY="0"; C_SELF_ADMIN=""; C_HOT_ADMIN=""; C_HOT_PROPOSER=""; C_HOT_EXECUTOR=""
C_HOT_CANCELLER=""; C_ROLE_READ=""
if [ "$LP_TO" != "$PROVIDER" ]; then
  LPT_L="$(lc "$LP_TO")"
  [ "$LPT_L" != "0x0000000000000000000000000000000000000000" ] \
    || die "LP_TO is address(0) -- LP minted there is LP destroyed, and the pool could never be pulled back"
  C_CODE="$(code_len "$RPC137" "$LP_TO")"
  if [ "$C_CODE" -le 0 ]; then
    [ "${LP_TO_HOT_ACK:-0}" = "1" ] || die "LP_TO $LP_TO has no code on $RPC137, so it is a wallet, not a timelock: whoever holds that key pulls the pool with no delay and no record. That is a legal decision (most DEX LPs are hot) but it contradicts the standing ruling, so it has to be said out loud: re-run with LP_TO_HOT_ACK=1 and record it as hot custody."
    CUSTODY_KIND="hot-eoa"
    say "custody: $LP_TO holds no code -- HOT CUSTODY acknowledged (LP_TO_HOT_ACK=1). The exit is one signature."
  else
    CUSTODY_KIND="timelock"
    C_MIN_DELAY="$(num "$(rd "$LP_TO" 'getMinDelay()(uint256)')")"
    [ -n "$C_MIN_DELAY" ] || die "could not read getMinDelay() from $LP_TO -- it is not a TimelockController, it only has code"
    [ "$(gt "$C_MIN_DELAY" 0)" = "1" ] || die "$LP_TO reports minDelay $C_MIN_DELAY -- a timelock with no delay is a wrapper, and custody behind it is custody behind the hot key wearing a different noun"
    C_ROLE_READ="$(one "$(rd "$LP_TO" 'PROPOSER_ROLE()(bytes32)')")"
    [ "$(lc "$C_ROLE_READ")" = "$(lc "$R_PROPOSER")" ] \
      || die "$LP_TO answers PROPOSER_ROLE = $C_ROLE_READ, not the role hash this planner expects -- its exit calldata would be wrong"
    # `isOperation` is what proves the TimelockController operation API the exit recipe depends on. A
    # contract that holds tokens but cannot queue-and-execute a call is a vault, not a timelock.
    ISOP="$(rd "$LP_TO" 'isOperation(bytes32)(bool)' 0x1111111111111111111111111111111111111111111111111111111111111111 2>/dev/null)"
    [ -n "$ISOP" ] || die "$LP_TO does not answer isOperation(bytes32) -- the schedule/execute path this custody needs is not there"
    hotrole(){ one "$(rd "$LP_TO" 'hasRole(bytes32,address)(bool)' "$1" "$PROVIDER")"; }
    C_HOT_ADMIN="$(hotrole "$R_ADMIN")"; C_HOT_PROPOSER="$(hotrole "$R_PROPOSER")"
    C_HOT_EXECUTOR="$(hotrole "$R_EXECUTOR")"; C_HOT_CANCELLER="$(hotrole "$R_CANCELLER")"
    C_SELF_ADMIN="$(one "$(rd "$LP_TO" 'hasRole(bytes32,address)(bool)' "$R_ADMIN" "$LP_TO")")"
    say "custody: $LP_TO is a TimelockController, minDelay $C_MIN_DELAY s ($(( C_MIN_DELAY / 3600 ))h), self-admin=$C_SELF_ADMIN"
    say "        provider $PROVIDER on it: DEFAULT_ADMIN=$C_HOT_ADMIN PROPOSER=$C_HOT_PROPOSER EXECUTOR=$C_HOT_EXECUTOR CANCELLER=$C_HOT_CANCELLER"
    if [ "$C_HOT_ADMIN" = "true" ]; then
      [ "${LP_TO_WEAK_ACK:-0}" = "1" ] || die "$LP_TO grants DEFAULT_ADMIN to the planning key $PROVIDER: that key can revoke and re-grant roles, so the $(( C_MIN_DELAY / 3600 ))h in front of the LP is removable with one signature. On Polygon 137 that is $LP_TO_WEAK_DEFAULT (measured true). The bridge timelock $LP_TO_DEFAULT does NOT grant it -- use that, or accept the weaker custody knowingly with LP_TO_WEAK_ACK=1."
      say "weak custody acknowledged with LP_TO_WEAK_ACK=1: the delay is movable by the same key that would use it"
    fi
    [ "${C_HOT_PROPOSER}" = "true" ] && [ "${C_HOT_EXECUTOR}" = "true" ] || {
      [ "${LP_EXIT_UNPROVEN_ACK:-0}" = "1" ] || die "$PROVIDER holds PROPOSER=$C_HOT_PROPOSER EXECUTOR=$C_HOT_EXECUTOR on $LP_TO, so the key this plan is signed with could not queue or run the removeLiquidity that gets the LP back. Minting into that custody makes the position unredeemable by us; fix the roles first (48 h once the delay is in force), or set LP_EXIT_UNPROVEN_ACK=1 if another key holds them."
      say "the planning key cannot drive the exit; LP_EXIT_UNPROVEN_ACK=1 was set, so a different key must hold PROPOSER+EXECUTOR"
    }
  fi
else
  CUSTODY_KIND="hot-self"
  say "custody: LP to the provider itself ($PROVIDER) -- hot, and it needs LP_TO_HOT_ACK=1 to be deliberate"
  [ "${LP_TO_HOT_ACK:-0}" = "1" ] || die "LP_TO=PROVIDER is hot custody: the same key that seeds the pool pulls it. Set LP_TO_HOT_ACK=1 to keep it, or leave LP_TO unset to use the timelock $LP_TO_DEFAULT."
fi

# ---------------------------------------------------------------- the provider must actually hold both sides
PB_W="$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$PROVIDER")")"
PB_U="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$PROVIDER")")"
PB_POL_RAW="$(result "$RPC137" eth_getBalance "$P_LATEST")"
PB_POL="$(int16 "$PB_POL_RAW")"
[ "$(ge "$PB_W" "$AMT_W")" = "1" ] || die "provider $PROVIDER holds $PB_W wei of $S_W and the pool needs $AMT_W -- move $S_W to it first (the founder holds all $SUP_W wei and has 0 POL, so that wallet cannot approve anything)"
[ "$(ge "$PB_U" "$AMT_U")" = "1" ] || die "provider $PROVIDER holds $PB_U wei of $S_U and the pool needs $AMT_U -- nobody in this project holds USDC on 137 today, so sourcing it is an owner money decision, not something to mint"
say "provider $PROVIDER holds $PB_W wei $S_W, $PB_U wei $S_U, $PB_POL wei POL"

PAIR_NOW="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
if [ "$(lc "$PAIR_NOW")" != "0x0000000000000000000000000000000000000000" ]; then
  [ "${ALLOW_EXISTING:-0}" = "1" ] || die "a $S_W/$S_U pair already exists at $PAIR_NOW -- adding to it prices against reserves this script did not set. Set ALLOW_EXISTING=1 only if that is intended."
  say "existing pair $PAIR_NOW acknowledged"
fi

LATEST="$(result "$RPC137" eth_getTransactionCount "$P_LATEST")"
LATEST="$(int16 "$LATEST")"
PENDING="$(result "$RPC137" eth_getTransactionCount "$P_PENDING")"
PENDING="$(int16 "$PENDING")"
[ "$LATEST" = "$PENDING" ] || die "$PROVIDER has a transaction in flight (latest $LATEST, pending $PENDING). Wait for it -- these nonces would collide with it."

MIN_W="$(python3 -c 'import sys;print(int(int(sys.argv[1]) * (10000 - int(sys.argv[2])) // 10000))' "$AMT_W" "$SLIPPAGE_BPS")"
MIN_U="$(python3 -c 'import sys;print(int(int(sys.argv[1]) * (10000 - int(sys.argv[2])) // 10000))' "$AMT_U" "$SLIPPAGE_BPS")"

# ---------------------------------------------------------------- fees and deadline, live
PRIORITY="$(int16 "$(result "$RPC137" eth_maxPriorityFeePerGas '[]')" 2>/dev/null || echo 3000000000)"
BLK="$(rpc "$RPC137" eth_getBlockByNumber '["latest",false]')"
BASE="$(printf '%s' "$BLK" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("result") or {};print(int(d.get("baseFeePerGas","0x1"),16))')"
NOWT="$(printf '%s' "$BLK" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("result") or {};print(int(d.get("timestamp","0x1"),16))')"
DEADLINE="$(python3 -c 'import sys;print(int(sys.argv[1]) + 3600)' "$NOWT")"
MAXFEE="$(python3 -c 'import sys;print(max(1, 2 * (int(sys.argv[1]) + int(sys.argv[2]))))' "$BASE" "$PRIORITY")"
say "fees: tip $PRIORITY wei, base $BASE wei, maxFee $MAXFEE wei; deadline $DEADLINE (chain time $NOWT + 1h)"

# ---------------------------------------------------------------- gas, mined on a fork of the real chain
printf '\n== mine approve, approve, addLiquidity on a fork of %s and take the gas from their receipts\n' "$RPC137"
anvil --fork-url "$RPC137" --chain-id 137 --port "$PLAN_FORK_PORT" --auto-impersonate >"$PLAN_DIR/anvil.log" 2>&1 &
ANVIL=$!
cleanup(){ kill "$ANVIL" 2>/dev/null || true; wait "$ANVIL" 2>/dev/null || true; }
trap 'cleanup' EXIT
ready=0
for _ in $(seq 1 90); do
  [ "$(result "$FORK" eth_chainId '[]')" = "0x89" ] && { ready=1; break; }
  sleep 1
done
[ "$ready" = "1" ] || die "the 137 fork did not answer chainId 0x89 -- see $PLAN_DIR/anvil.log"

send_fork(){ cast send --rpc-url "$FORK" --unlocked --from "$1" "$2" "$3" "${@:4}" 2>&1 | tee "$PLAN_DIR/last-send.log" \
  | awk '$1=="transactionHash"{print $2}' | head -1; }
rfield(){ rpc "$FORK" eth_getTransactionReceipt "[\"$1\"]" | python3 -c 'import sys,json
d=(json.load(sys.stdin).get("result") or {})
k=sys.argv[1]; v=d.get(k)
print(v if k=="status" else (int(v,16) if v else ""))' "$2"; }

AP_W="$(cast calldata 'approve(address,uint256)' "$ROUTER" "$AMT_W")"
AP_U="$(cast calldata 'approve(address,uint256)' "$ROUTER" "$AMT_U")"
AL_SIG='addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)'
AL="$(cast calldata "$AL_SIG" "$WLXON" "$USDC" "$AMT_W" "$AMT_U" "$MIN_W" "$MIN_U" "$LP_TO" "$DEADLINE")"
for pair in "approve(address,uint256)|$AP_W" "$AL_SIG|$AL"; do
  sig="${pair%%|*}"; data="${pair#*|}"; sel="$(cast sig "$sig")"
  [ "$(printf '%s' "$data" | cut -c1-10)" = "$sel" ] || die "calldata for $sig does not begin with its own selector $sel"
done

h1="$(send_fork "$PROVIDER" "$WLXON" 'approve(address,uint256)' "$ROUTER" "$AMT_W")"
[ -n "$h1" ] || die "the fork refused the $S_W approve: $(head -c 220 "$PLAN_DIR/last-send.log")"
[ "$(rfield "$h1" status)" = "0x1" ] || die "the $S_W approve reverted on the fork: $(head -c 220 "$PLAN_DIR/last-send.log")"
G1="$(rfield "$h1" gasUsed)"
h2="$(send_fork "$PROVIDER" "$USDC" 'approve(address,uint256)' "$ROUTER" "$AMT_U")"
[ -n "$h2" ] || die "the fork refused the $S_U approve: $(head -c 220 "$PLAN_DIR/last-send.log")"
[ "$(rfield "$h2" status)" = "0x1" ] || die "the $S_U approve reverted on the fork: $(head -c 220 "$PLAN_DIR/last-send.log")"
G2="$(rfield "$h2" gasUsed)"
h3="$(send_fork "$PROVIDER" "$ROUTER" "$AL_SIG" "$WLXON" "$USDC" "$AMT_W" "$AMT_U" "$MIN_W" "$MIN_U" "$LP_TO" "$DEADLINE")"
[ -n "$h3" ] || die "the fork refused addLiquidity: $(head -c 300 "$PLAN_DIR/last-send.log")"
[ "$(rfield "$h3" status)" = "0x1" ] || die "addLiquidity reverted on the fork, so the live batch would too: $(head -c 300 "$PLAN_DIR/last-send.log")"
G3="$(rfield "$h3" gasUsed)"

# The external anchor: ask the PAIR what it received, rather than restating what this script sent. A
# guard that re-quotes its own inputs can only fail on a typo in the guard.
PAIR="$(one "$(rdf "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
[ "$(lc "$PAIR")" != "0x0000000000000000000000000000000000000000" ] || die "the batch mined but the factory names no pair -- this is not the pool the plan describes"
R0="$(one "$(rdf "$PAIR" 'getReserves()(uint112,uint112,uint32)')")"
R1="$(rdf "$PAIR" 'getReserves()(uint112,uint112,uint32)' | awk 'NR==2{print $1}')"
TOK0="$(one "$(rdf "$PAIR" 'token0()(address)')")"
LPX="$(num "$(rdf "$PAIR" 'balanceOf(address)(uint256)' "$LP_TO")")"
LPP="$(num "$(rdf "$PAIR" 'balanceOf(address)(uint256)' "$PROVIDER")")"
if [ "$(lc "$TOK0")" = "$(lc "$WLXON")" ]; then WANT0="$AMT_W"; WANT1="$AMT_U"; else WANT0="$AMT_U"; WANT1="$AMT_W"; fi
[ "$R0" = "$WANT0" ] || die "the pair's token0 reserve is $R0, the plan sends $WANT0 -- token0 is $TOK0"
[ "$R1" = "$WANT1" ] || die "the pair's token1 reserve is $R1, the plan sends $WANT1"
[ "$(gt "$LPX" 0)" = "1" ] || die "the fork minted no LP to the custody address $LP_TO -- the liquidity went somewhere else, or that address cannot receive it"
[ "$LPP" = "0" ] || die "the fork left $LPP LP with the provider while custody was named as $LP_TO -- the to-argument did not take"
say "fork pair $PAIR: reserves match both sides exactly, $LPX LP minted to custody $LP_TO and 0 to the provider"
cleanup; trap - EXIT

# Fork-mined gas x 1.15, with an optional floor. GAS_FLOOR can only raise a cap, never lower one -- measured
# the hard way on 2026-10-29: the anvil fork priced `approve` on the bridged-USDC proxy at 58,097, the plan
# capped it at 66,813, and the LIVE transaction (0x629aa652…a7ae) reverted `out of gas` inside the proxy's
# DELEGATECALL even though an eth_call of the identical calldata against the same state returned success.
# A proxy's first cold SSTORE is cheaper on a fork that has already touched the slot during planning, which
# is exactly the case a rehearsal cannot cover. Cap is a floor on the network's charge, not a spend: unused
# gas is returned, so the only cost of a wider cap is that the wallet must be able to *cover* cap x maxFee.
bump(){ python3 -c 'import sys,os
g=int(sys.argv[1]); out=int(g*115//100)+1
f=int(os.environ.get("GAS_FLOOR","0") or 0)
print(out if f < out else f)' "$1"; }
GA1="$(bump "$G1")"; GA2="$(bump "$G2")"; GA3="$(bump "$G3")"
N0="$LATEST"
N1="$(python3 -c 'import sys;print(int(sys.argv[1]) + 1)' "$N0")"
N2="$(python3 -c 'import sys;print(int(sys.argv[1]) + 2)' "$N0")"

python3 "$PLAN_LIB" add "approve-wlxon" "$N0" "$(lc "$WLXON")" 0 "$AP_W" "$GA1" "$MAXFEE" "$PRIORITY" \
  137 "$PROVIDER" "fork gasUsed $G1 x1.15" "hand the router $AMT_W wei of $S_W"
python3 "$PLAN_LIB" add "approve-usdc" "$N1" "$(lc "$USDC")" 0 "$AP_U" "$GA2" "$MAXFEE" "$PRIORITY" \
  137 "$PROVIDER" "fork gasUsed $G2 x1.15" "hand the router $AMT_U wei of $S_U"
python3 "$PLAN_LIB" add "add-liquidity" "$N2" "$(lc "$ROUTER")" 0 "$AL" "$GA3" "$MAXFEE" "$PRIORITY" \
  137 "$PROVIDER" "fork gasUsed $G3 x1.15" "seed $AMOUNT_WLXON $S_W + $AMOUNT_USDC $S_U, LP to custody $LP_TO ($CUSTODY_KIND)"

PLAN_START_NONCE="$N0" PLAN_CHAIN_ID=137 PLAN_DEPLOYER="$PROVIDER" PLAN_RPC="$RPC137" \
PLAN_MAX_FEE="$MAXFEE" PLAN_PRIORITY_FEE="$PRIORITY" PLAN_PHASE="pool-wlxon-usdc" PLAN_STAMP="$PLAN_STAMP" \
PLAN_FEE_SOURCE="2x live base+tip" PLAN_CAPS_SOURCE="mined on an anvil fork of Polygon 137" \
PLAN_LEGACY_ADDR="$USDC" PLAN_PREDICTED_WLXON="$WLXON" \
  python3 "$PLAN_LIB" finish | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  plan.json: %s (%d tx, nonce %d, %d gas)" % (d["plan"],d["transactions"],d["startNonce"],d["totalGas"]))'

# Annotate plan.json with the price and what KIND of price it is. Written after finish because
# plan137.py has no pool vocabulary -- and a launch record that omits this line is the one that gets
# quoted back later as a market price.
PLAN_JSON="$PLAN_DIR/plan.json" POOL_PROVIDER="$PROVIDER" POOL_WLXON="$WLXON" POOL_SW="$S_W" POOL_DW="$D_W" \
POOL_AMTW="$AMT_W" POOL_USDC="$USDC" POOL_SU="$S_U" POOL_DU="$D_U" POOL_AMTU="$AMT_U" POOL_PRICE="$PRICE" \
POOL_PAIR="$PAIR" POOL_ROUTER="$ROUTER" POOL_FACTORY="$FACTORY" POOL_G1="$G1" POOL_G2="$G2" POOL_G3="$G3" \
POOL_MINW="$MIN_W" POOL_MINU="$MIN_U" POOL_DEADLINE="$DEADLINE" POOL_SLIP="$SLIPPAGE_BPS" POOL_LP="$LPX" \
POOL_LP_PROVIDER="$PROVIDER" POOL_LPTO="$LP_TO" POOL_CKIND="$CUSTODY_KIND" POOL_CDELAY="$C_MIN_DELAY" \
POOL_CADMIN_SELF="$C_SELF_ADMIN" POOL_CADMIN_HOT="$C_HOT_ADMIN" POOL_CPROP="$C_HOT_PROPOSER" \
POOL_CEXEC="$C_HOT_EXECUTOR" POOL_CCANC="$C_HOT_CANCELLER" POOL_ROLE_READ="$C_ROLE_READ" \
POOL_RPROPOSER="$R_PROPOSER" POOL_HEXEC="$R_EXECUTOR" \
python3 <<'PY'
import json, os
e = os.environ
p = e["PLAN_JSON"]
d = json.load(open(p))
d["pool"] = {
    "venue": "QuickSwap V2 (Polygon 137)", "factory": e["POOL_FACTORY"], "router": e["POOL_ROUTER"],
    "provider": e["POOL_PROVIDER"],
    "lpRecipient": e["POOL_LPTO"],
    "tokenA": {"address": e["POOL_WLXON"], "symbol": e["POOL_SW"], "decimals": int(e["POOL_DW"]),
               "amountWei": int(e["POOL_AMTW"]), "amountMin": int(e["POOL_MINW"])},
    "tokenB": {"address": e["POOL_USDC"], "symbol": e["POOL_SU"], "decimals": int(e["POOL_DU"]),
               "amountWei": int(e["POOL_AMTU"]), "amountMin": int(e["POOL_MINU"])},
    "slippageBps": int(e["POOL_SLIP"]), "deadline": int(e["POOL_DEADLINE"]),
    "priceImpliedUsdcPerWlxon": float(e["POOL_PRICE"]),
    "priceKind": "SELF-DEALT: this batch's split IS the price. No counterparty, no outside bid, one pool.",
    "forkPairCreated": e["POOL_PAIR"], "lpTokensMintedOnFork": int(e["POOL_LP"]),
    "forkGasUsed": {"approveWlxon": int(e["POOL_G1"]), "approveUsdc": int(e["POOL_G2"]),
                    "addLiquidity": int(e["POOL_G3"])},
}
d["custody"] = {
    "kind": e["POOL_CKIND"],
    "address": e["POOL_LPTO"],
    "minDelaySeconds": int(e["POOL_CDELAY"]) if e["POOL_CDELAY"].isdigit() else None,
    "proposerRoleHash": e["POOL_ROLE_READ"],
    "measured": {
        "selfIsDefaultAdmin": e["POOL_CADMIN_SELF"],
        "providerIsDefaultAdmin": e["POOL_CADMIN_HOT"],
        "providerIsProposer": e["POOL_CPROP"],
        "providerIsExecutor": e["POOL_CEXEC"],
        "providerIsCanceller": e["POOL_CCANC"],
    },
    "exit": {
        "shape": "TimelockController.scheduleBatch then executeBatch, minDelay apart",
        "steps": [
            "pair.approve(router, lpBalance)  -- executed BY the timelock, so the allowance is its own",
            "router.removeLiquidity(wLxon, usdc, lp, amountAMin, amountBMin, recipient, deadline)",
        ],
        "note": "Custody without a proven exit is a burn. RehearsePoolCustody137.sh proves this exact "
                "batch on a fork of Polygon 137, including that it is refused before minDelay elapses.",
    },
}
json.dump(d, open(p, "w"), indent=1)
with open(p.replace("plan.json", "MANIFEST.txt"), "a") as fh:
    fh.write("\npool          : %s/%s on QuickSwap V2 (factory %s, router %s)\n"
             % (e["POOL_SW"], e["POOL_SU"], e["POOL_FACTORY"], e["POOL_ROUTER"]))
    fh.write("split         : %s wei %s + %s wei %s  ->  1 %s = %s %s\n"
             % (e["POOL_AMTW"], e["POOL_SW"], e["POOL_AMTU"], e["POOL_SU"], e["POOL_SW"],
                e["POOL_PRICE"], e["POOL_SU"]))
    fh.write("price kind    : SELF-DEALT. The split above is the only thing setting this number, and it\n")
    fh.write("                becomes the price anyone quoting %s reads. Record it as such.\n" % e["POOL_SW"])
    fh.write("fork proof    : pair %s created on a fork of the live chain, both reserves matched to the\n" % e["POOL_PAIR"])
    fh.write("                wei, %s LP minted to %s -- the gas limits above are those receipts x1.15\n"
             % (e["POOL_LP"], e["POOL_PROVIDER"]))
    fh.write("custody       : %s LP to %s (%s)\n" % (e["POOL_SW"], e["POOL_LPTO"], e["POOL_CKIND"]))
    if e["POOL_CKIND"] == "timelock":
        fh.write("                TimelockController, minDelay %ss (%dh). Measured on the endpoint this plan\n"
                 % (e["POOL_CDELAY"], int(e["POOL_CDELAY"]) // 3600))
        fh.write("                was planned against: self DEFAULT_ADMIN=%s, provider DEFAULT_ADMIN=%s\n"
                 % (e["POOL_CADMIN_SELF"], e["POOL_CADMIN_HOT"]))
        fh.write("                provider PROPOSER=%s EXECUTOR=%s CANCELLER=%s\n"
                 % (e["POOL_CPROP"], e["POOL_CEXEC"], e["POOL_CCANC"]))
        fh.write("                Exit is TWO timed calls, 48h apart: scheduleBatch(pair.approve +\n")
        fh.write("                router.removeLiquidity) then executeBatch. Prove it with\n")
        fh.write("                RehearsePoolCustody137.sh before anyone is promised the LP is redeemable.\n")
    else:
        fh.write("                HOT CUSTODY (%s): the key that holds this can pull the pool at any moment\n"
                 % e["POOL_CKIND"])
        fh.write("                with no delay and no on-chain notice. Say so in the launch record.\n")
    fh.write("expiry        : deadline %s (chain time + 1 h). If signing takes longer, re-plan; do not\n" % e["POOL_DEADLINE"])
    fh.write("                hand-edit the deadline into a signature.\n")
print("  pool annotated: 1 %s = %s %s (self-dealt)" % (e["POOL_SW"], e["POOL_PRICE"], e["POOL_SU"]))
PY

[ -f "$PLAN_DIR/plan.json" ] || die "the plan writer produced no $PLAN_DIR/plan.json"
rm -f "$PLAN_DIR/last-send.log"

printf '\n== planned. Nothing was signed and nothing was broadcast.\n'
printf '   %s/plan.json   %s/MANIFEST.txt\n' "$PLAN_DIR" "$PLAN_DIR"
printf '   custody: the LP lands at %s (%s)\n' "$LP_TO" "$CUSTODY_KIND"
if [ "$CUSTODY_KIND" = "timelock" ]; then
  printf '   that means pulling this liquidity later is a %dh operation: schedule the\n' "$(( C_MIN_DELAY / 3600 ))"
  printf '   approve+removeLiquidity batch, wait it out, execute it. Prove the exit first with\n'
  printf '     bash script/polygon137/RehearsePoolCustody137.sh\n'
fi
printf '   next, on the machine holding the provider keystore:\n'
printf '     PLAN_DIR="%s" KEYSTORE=<keystore> PASSWORD_FILE=<pw-file> bash script/polygon137/SignWlxon137Plan.sh\n' "$PLAN_DIR"
printf '   then, from anywhere that can reach %s:\n' "$RPC137"
printf '     PLAN_DIR="%s" SIGNED_DIR="%s/signed" bash script/polygon137/BroadcastWlxon137Signed.sh\n' "$PLAN_DIR" "$PLAN_DIR"
