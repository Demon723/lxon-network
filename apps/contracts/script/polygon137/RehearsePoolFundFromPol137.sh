#!/usr/bin/env bash
# Answer "use the remaining POL to complete this" with a run, not an opinion.
#
#   bash script/polygon137/RehearsePoolFundFromPol137.sh
#
# The owner ruling of 2026-10-29 sizes the pool at 10,000 wLXON + 2,356 native USDC (1 wLXON = $0.2356),
# the 10,000 wLXON crossed and is sitting in the launch key, and the USDC leg has never existed anywhere in
# this project. The instruction on the table is to fund it from the POL that IS in the wallet. This run
# drives that route end to end on a fork of Polygon so the answer is measured rather than argued:
#
#   1. reads the live launch key's POL and asks the LIVE router what the venue would actually pay for it;
#   2. swaps it on a fork with the real router and MEASURES the gas, keeping back what the create batch
#      needs to exist before it can be signed (a signed transaction with no gas is a signed transaction
#      that cannot be published);
#   3. sizes the wLXON leg so the ruled price survives -- the split IS the price, so a POL-funded pool
#      that kept $0.2356 is a pool of 5-ish tokens, not 10,000;
#   4. plans it with the real PlanPool137.sh, replays the plan's own bytes, and shows the LP landing in the
#      custody timelock;
#   5. takes the liquidity back out through the 48 h timelock and re-measures the POL that is left, so the
#      run states whether the wallet can still afford the exit it just promised;
#   6. re-reads production and fails if any of this moved anything real.
#
# Nothing is signed here and no launch key is used: the fork runs --auto-impersonate, so the deployer
# address drives the calls without its keystore being present. The swap uses amountOutMin = 0 because it is
# a rehearsal of a route, not a launch; the live batch is planned with zero slippage by the planner.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC137_SRC="${RPC137_SRC:-https://polygon.drpc.org}"
P137="${P137_PORT:-19006}"
F137="http://127.0.0.1:$P137"
PLAN_PORT="${PLAN_FORK_PORT:-19016}"
WLXON=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
WETH=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
REF_PAIR=0x6D9e8dbB2779853db00418D4DcF96F3987CFC9D2                 # WMATIC/USDC -- the only USDC on this venue
DEPLOYER=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
FOUNDER=0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3
STRONG_TL=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5
ZERO=0x0000000000000000000000000000000000000000
Z32=0x0000000000000000000000000000000000000000000000000000000000000000
SALT_A=0x000000000000000000000000000000000000000000000000000000000000c0de
R_PROPOSER=0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1
# The ruled price. The pool may be smaller than the ruling; it must not be CHEAPER than the ruling, because
# the number anyone quotes off this venue is the split this batch chose.
TARGET_PRICE="${TARGET_PRICE_USDC_PER_WLXON:-0.2356}"
# What has to stay in the wallet before a swap is allowed to take POL away: the create batch is capped by the
# planner at gasUsed x 1.15 with a maxFee that must be payable up front (the earlier run measured 2,820,587 gas at a 932 gwei cap = 2.629 POL;
# this one re-measures the caps and asserts against them rather than against this comment), the swap itself is ~1e5 gas, and the exit batch is 312,748. 3.3 POL covers all three with
# margin; the run asserts the split rather than trusting the round number.
KEEP_POL="${KEEP_POL_WEI:-3300000000000000000}"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$*"; }
bad(){ FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$*"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
note(){ printf '  ·    %s\n' "$*"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
j(){ curl -s --max-time 120 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
rpc(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}"; }
result(){ rpc "$1" "$2" "$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result") or "")' 2>/dev/null; }
jp(){ printf '["%s","%s"]' "$1" "$2"; }
one(){ printf '%s\n' "$1" | awk 'NR==1{print $1}'; }
num(){ printf '%s\n' "$1" | awk 'NR==1{print $1}' | tr -cd '0-9'; }
# num reads an ARGUMENT; numd reads a PIPE. They are not interchangeable, and calling `... | num` starts a
# second failure mode far from the cause: under `set -u` it dies with `$1: unbound variable` on the line the
# helper is DEFINED on, so every number after it in the run is empty and the assertions read as money bugs.
numd(){ awk 'NR==1{print $1}' | tr -cd '0-9'; }
hexd(){ python3 -c 'import sys
s=sys.stdin.read().strip().strip(chr(34))
print(int(s,16) if s else "")' 2>/dev/null; }
gt(){ python3 -c 'import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))' "$1" "$2"; }
ge(){ python3 -c 'import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))' "$1" "$2"; }
le(){ python3 -c 'import sys;print(int(int(sys.argv[1]) <= int(sys.argv[2])))' "$1" "$2"; }
pct(){ python3 -c 'import sys;print(int(sys.argv[1]) * int(sys.argv[2]) // 100)' "$1" "$2"; }
close(){ python3 -c 'import sys
a=float(sys.argv[1]); b=float(sys.argv[2]); t=float(sys.argv[3])
print(int(abs(a-b) <= abs(t)*float(sys.argv[4])))' "$1" "$2" "$3" "$4"; }
# cast prints a uint256[] as ONE line -- `[16000000000000000000 [1.6e19], 1465736 [1.465e6]]` -- so tail -1
# on it is the whole array and `tr -cd 0-9` glues every digit in that line into one meaningless integer
# (measured: it returned 160000000000000000001619146573614656 for the quote above). amt_last is the parse
# that survives the "[scientific]" suffix: strip the brackets, split the elements, take the first field.
amt_last(){ python3 -c 'import sys
s=sys.stdin.read().strip()
if s.startswith("["): s=s[1:]
if s.endswith("]"): s=s[:-1]
parts=[p.strip() for p in s.split(",") if p.strip()]
print(parts[-1].split()[0] if parts else "")' 2>/dev/null; }
rpc_read(){ local out i
  for i in 1 2 3; do
    out="$(cast call "$@" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 1
  done; printf '\n'; return 1; }
rd(){ rpc_read "$1" "$2" "${@:3}" --rpc-url "$F137"; }
rdlive(){ rpc_read "$1" "$2" "${@:3}" --rpc-url "$RPC137_SRC"; }
ts(){ rpc "$F137" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;d=json.load(sys.stdin).get("result") or {};print(int(d.get("timestamp","0x1"),16))'; }
send(){ cast send --rpc-url "$F137" --unlocked --from "$1" "$2" "$3" "${@:4}" 2>&1 | tee "$ROOT/last.log" \
  | awk '$1=="transactionHash"{print $2}' | head -1; }
sendv(){ cast send --rpc-url "$F137" --unlocked --from "$1" --value "$4" "$2" "$3" "${@:5}" 2>&1 | tee "$ROOT/swap.log" \
  | awk '$1=="transactionHash"{print $2}' | head -1; }
# The envelope is decoded ONCE here. Routing a receipt through `result` and then json.load again is the bug
# that made a green fork transaction read as "no-tx".
status(){ [ -z "$1" ] && { printf 'no-tx\n'; return; }
  rpc "$F137" eth_getTransactionReceipt "[\"$1\"]" \
  | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("status","not-mined"))' 2>/dev/null; }
gask(){ rpc "$F137" eth_getTransactionReceipt "[\"$1\"]" \
  | python3 -c 'import sys,json;d=(json.load(sys.stdin).get("result") or {});print(int(d.get("gasUsed","0x0"),16) if d.get("gasUsed") else "")' 2>/dev/null; }
pltxdata(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["data"])' "$PLAN/plan.json" "$1"; }
pltxto(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["to"])' "$PLAN/plan.json" "$1"; }
pltxlabel(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["label"])' "$PLAN/plan.json" "$1"; }
pltxgas(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["gas"])' "$PLAN/plan.json" "$1"; }
pltxfee(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["maxFeePerGas"])' "$PLAN/plan.json" "$1"; }

ROOT="$(mktemp -d /tmp/lxon-pool-polfund.XXXXXX)"
PLAN="$ROOT/plan"; mkdir -p "$PLAN"
A137=""
cleanup(){ [ -n "$A137" ] && kill "$A137" 2>/dev/null; wait 2>/dev/null || true
  case "$ROOT" in /tmp/lxon-pool-polfund.*) rm -rf "$ROOT";; esac; }
trap 'cleanup' EXIT

say "0. the venue and the wallet, read from the LIVE chain before anything is forked"
LIVE_POL="$(result "$RPC137_SRC" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)"
[ -n "$LIVE_POL" ] || { bad "could not read the launch key's POL from $RPC137_SRC -- nothing below means anything"; exit 1; }
LIVE_NONCE="$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)"
LIVE_HEAD="$(result "$RPC137_SRC" eth_blockNumber '[]' | hexd)"
LIVE_TS="$(rpc "$RPC137_SRC" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
LIVE_PAIR="$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "$ZERO" "$(lc "$LIVE_PAIR")" "mainnet has no wLXON/USDC pair (this run must not create one)"
LIVE_SUP="$(num "$(rdlive "$WLXON" 'totalSupply()(uint256)')")"
LIVE_W="$(num "$(rdlive "$WLXON" 'balanceOf(address)(uint256)' "$DEPLOYER")")"
LIVE_U="$(num "$(rdlive "$USDC" 'balanceOf(address)(uint256)' "$DEPLOYER")")"
eq "0" "$LIVE_U" "the launch key holds zero USDC today -- the whole question is whether POL can become some"
note "live: POL $LIVE_POL wei, nonce $LIVE_NONCE, wLXON $LIVE_W of $LIVE_SUP supply, head $LIVE_HEAD"
# The two quotes that decide the answer, taken from the router itself rather than from my own arithmetic.
Q_FULL="$(rdlive "$ROUTER" 'getAmountsOut(uint256,address[])(uint256[])' "$LIVE_POL" "[$WETH,$USDC]" | amt_last)"
Q_KEEP="$(python3 -c 'import sys;print(int(sys.argv[1])-int(sys.argv[2]))' "$LIVE_POL" "$KEEP_POL")"
Q_KEEP_USDC="$(rdlive "$ROUTER" 'getAmountsOut(uint256,address[])(uint256[])' "$Q_KEEP" "[$WETH,$USDC]" | amt_last)"
Q_RULED_POL="$(rdlive "$ROUTER" 'getAmountsOut(uint256,address[])(uint256[])' "2356000000" "[$USDC,$WETH]" | amt_last)"
[ -n "$Q_FULL" ] && [ "$Q_FULL" != "0" ] && ok "the router pays $Q_FULL wei USDC ($(python3 -c 'import sys;print("%.4f" % (int(sys.argv[1])/10**6))' "$Q_FULL") USDC) for every POL in the key -- that is the ceiling" || bad "getAmountsOut gave [$Q_FULL] on $RPC137_SRC"
eq "1" "$(gt "$Q_FULL" "$Q_KEEP_USDC")" "and taking the signing reserve out first pays less: $Q_KEEP_USDC wei for $Q_KEEP POL"
note "the ruled 2,356 USDC is priced by this venue at $Q_RULED_POL wei POL -- $(python3 -c 'import sys;print("%.0f" % (int(sys.argv[1])/10**18))' "$Q_RULED_POL") POL"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))' "$Q_RULED_POL" "$LIVE_POL")" \
   "which is more POL than exists in the whole project, so the ruling cannot be funded from this wallet"
RES="$(rdlive "$REF_PAIR" 'getReserves()(uint112,uint112,uint32)' | tr '\n' ' ')"
note "the WMATIC/USDC pair that has to supply it: $RES -- one line, both legs, read from the pair"

say "1. a fork of Polygon 137 (port must be free -- a stale fork carries the previous run's +48 h warp)"
if [ -n "$(rpc "$P137" eth_chainId '[]' 2>/dev/null | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or ""))' 2>/dev/null)" ]; then
  bad "port $P137 is already serving an RPC -- kill it and re-run rather than joining a leftover fork"
  exit 1
fi
anvil --fork-url "$RPC137_SRC" --chain-id 137 --port "$P137" --auto-impersonate >"$ROOT/anvil.log" 2>&1 & A137=$!
up=0
for _ in $(seq 1 120); do
  [ "$(result "$F137" eth_chainId '[]')" = "0x89" ] && { up=1; break; }
  sleep 1
done
[ "$up" = "1" ] || { tail -8 "$ROOT/anvil.log"; bad "the fork did not answer chainId 0x89"; exit 1; }
eq "alive" "$(kill -0 "$A137" 2>/dev/null && echo alive)" "the anvil THIS run started owns port $P137"
FORK_TS="$(rpc "$F137" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
GAP="$(python3 -c 'import sys;print(abs(int(sys.argv[1]) - int(sys.argv[2])))' "$FORK_TS" "$LIVE_TS")"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) < 300))' "$GAP")" "fork clock is within 300 s of live ($GAP s)"
eq "$ZERO" "$(lc "$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" "this fork is clean: no pair on it yet"
eq "$LIVE_POL" "$(result "$F137" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)" "and it mirrors the launch key's real POL balance"

say "2. swap the POL for USDC through the real router and measure what it actually costs"
SWAP_IN="$Q_KEEP"
DL="$(python3 -c 'import sys;print(int(sys.argv[1])+3600)' "$FORK_TS")"
h="$(sendv "$DEPLOYER" "$ROUTER" 'swapExactETHForTokens(uint256,address[],address,uint256)' "$SWAP_IN" "0" "[$WETH,$USDC]" "$DEPLOYER" "$DL")"
[ -n "$h" ] || { head -c 400 "$ROOT/swap.log"; bad "the swap produced no transaction at all"; exit 1; }
eq "0x1" "$(status "$h")" "swapExactETHForTokens mined on the fork (POL -> WETH -> USDC)"
GSWAP="$(gask "$h")"
note "measured swap gasUsed: $GSWAP (the plan's own caps are priced the same way -- from a mined receipt, never eth_estimateGas)"
U_GOT="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$DEPLOYER")")"
eq "1" "$(gt "$U_GOT" 0)" "the launch key now holds USDC for the first time in this project's history: $U_GOT wei"
eq "1" "$(close "$U_GOT" "$Q_KEEP_USDC" "$Q_KEEP_USDC" 0.02)" \
   "the venue delivered within 2% of the pre-trade live quote ($Q_KEEP_USDC wei quoted, $U_GOT wei mined)"
POL_LEFT="$(result "$F137" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)"
eq "1" "$(ge "$POL_LEFT" 2000000000000000000)" "and $POL_LEFT wei POL is left -- enough to sign the batch planned below"

say "3. the size the ruled price forces once the money is only \$1 of USDC"
AMT_U="$U_GOT"
# Decimal, not float, and one line of python: bash 3.2 cannot parse a multi-line `python3 -c` inside a
# command substitution and reports it as `$1: unbound variable` on the line the substitution STARTS on
# (measured: this run died here with the money already correct two assertions above). w_wei = u_wei/1e6/p
# * 1e18 = u_wei * 1e12 / p, and int() floors, so the split lands a hair cheap rather than a hair dear.
AMT_W="$(python3 -c 'import sys;from decimal import Decimal;print(int(Decimal(sys.argv[1])*Decimal(10)**12/Decimal(sys.argv[2])))' "$AMT_U" "$TARGET_PRICE")"
AMOUNT_WLXON_S="$(python3 -c 'import sys;from decimal import Decimal;print(Decimal(sys.argv[1])/Decimal(10)**18)' "$AMT_W")"
AMOUNT_USDC_S="$(python3 -c 'import sys;from decimal import Decimal;print(Decimal(sys.argv[1])/Decimal(10)**6)' "$AMT_U")"
note "a POL-funded pool at the ruled $TARGET_PRICE USDC per wLXON is $AMOUNT_USDC_S USDC + $AMOUNT_WLXON_S wLXON"
eq "1" "$(le "$AMT_W" "$LIVE_W")" "which is inside the 10,000 wLXON the crossing delivered"
eq "1" "$(le "$AMT_W" "$LIVE_SUP")" "and inside the whole wLXON supply"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) < int(sys.argv[2]) // 1000))' "$AMT_W" "$LIVE_W")" \
   "and that is the finding: the POL buys a pool of $(python3 -c 'import sys;print("%.2f" % (int(sys.argv[1])/10**18))' "$AMT_W") wLXON, not 10,000 -- $(python3 -c 'import sys;print("%.0f" % (10000 / (int(sys.argv[1])/10**18)))' "$AMT_W")x smaller"

say "4. plan it with the real planner, against the fork, custody left at its default"
RPC137="$F137" PROVIDER="$DEPLOYER" WLXON="$WLXON" USDC=native AMOUNT_WLXON="$AMOUNT_WLXON_S" \
  AMOUNT_USDC="$AMOUNT_USDC_S" POOL_SELFDEALT_ACK=1 PLAN_DIR="$PLAN" PLAN_FORK_PORT="$PLAN_PORT" \
  bash script/polygon137/PlanPool137.sh >"$ROOT/plan.log" 2>&1
eq "0" "$?" "the planner exited 0 on a pool it can describe honestly"
PLAN_PRICE="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'/plan.json"))["pool"]["priceImpliedUsdcPerWlxon"])')"
eq "1" "$(close "$PLAN_PRICE" "$TARGET_PRICE" "$TARGET_PRICE" 0.001)" \
   "the plan's implied price is $PLAN_PRICE USDC/wLXON -- the ruled number, not a new one"
eq "$(lc "$STRONG_TL")" "$(lc "$(python3 -c 'import json;print(json.load(open("'"$PLAN"'/plan.json"))["custody"]["address"])')")" \
   "and the LP destination is the bridge timelock, the ruling's custody"
eq "3" "$(python3 -c 'import json;print(len(json.load(open("'"$PLAN"'/plan.json"))["txs"]))')" "three transactions: approve, approve, addLiquidity"
TOTGAS="$(python3 -c 'import json;print(sum(int(t["gas"]) for t in json.load(open("'"$PLAN"'/plan.json"))["txs"]))')"
NOTEED="$(python3 -c 'import json;print(sum(int(t["gas"])*int(t["maxFeePerGas"]) for t in json.load(open("'"$PLAN"'/plan.json"))["txs"]))')"
note "planned caps: $TOTGAS gas total, $NOTEED wei POL must EXIST for the signatures to be publishable"
eq "1" "$(ge "$POL_LEFT" "$NOTEED")" "the wallet has $POL_LEFT wei after the swap, which clears that"
# gwei is 1e9 wei, so cost_wei = gas x fee_gwei x 1e9 and POL = that / 1e18. The first draft of this line
# divided by BOTH 1e9 and 1e18 and printed "0.0000 POL" for a batch that really costs 0.9 POL -- a units
# bug in a summary is the worst kind, because the number looks like a finding.
COST_E="$(python3 -c 'import sys;print("%.4f" % (int(sys.argv[1])*278*10**9/10**18))' "$TOTGAS")"
eq "1" "$(gt "$TOTGAS" 2000000)" "the create batch is $TOTGAS gas, which at the measured ~278 gwei effective fee costs $COST_E POL"

say "5. replay the plan's own bytes and watch where the LP goes"
# The amounts the plan actually wrote, not the ones this script passed in: the planner re-derives wei from
# the decimal string, and a rehearsal that compares against its own input can only ever agree with itself.
AMT_W_PLAN="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'/plan.json"))["pool"]["tokenA"]["amountWei"])')"
AMT_U_PLAN="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'/plan.json"))["pool"]["tokenB"]["amountWei"])')"
eq "1" "$(close "$AMT_W_PLAN" "$AMT_W" "$AMT_W" 0.0001)" "the plan's wLXON leg is the size the price implied ($AMT_W_PLAN wei)"
# <= 2 wei, not equality: the planner converts the decimal string with `float(x) * 10**decimals`, and
# float("1.282219") * 10**6 is 1282218.9999999998, so int() can land one wei under the wallet's balance.
# The consequence is a 1-wei dust note left behind, not a wrong price -- but a rehearsal that demanded exact
# equality would have read as a bug in the money rather than in the parse.
eq "1" "$(python3 -c 'import sys;print(int(abs(int(sys.argv[1])-int(sys.argv[2])) <= 2))' "$AMT_U" "$AMT_U_PLAN")" \
   "and its USDC leg is what the swap produced, to within the float parse ($AMT_U -> $AMT_U_PLAN wei)"
for i in 0 1; do
  hh="$(send "$DEPLOYER" "$(pltxto "$i")" "$(pltxdata "$i")")"
  eq "0x1" "$(status "$hh")" "planned tx $i ($(pltxlabel "$i")) mined from the plan's bytes"
done
h="$(send "$DEPLOYER" "$ROUTER" "$(pltxdata 2)")"
eq "0x1" "$(status "$h")" "planned tx 2 (addLiquidity) mined -- the pair now exists on the fork"
GADD="$(gask "$h")"
note "measured addLiquidity-first-time gasUsed: $GADD (planner assumed $(pltxgas 2))"
PAIR="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
if [ "$(lc "$PAIR")" = "$(lc "$ZERO")" ]; then
  bad "the factory still names no pair after the planned addLiquidity -- the seed did not happen, so sections 5-6 cannot mean anything"
  exit 1
fi
ok "getPair(wLXON, USDC) = $PAIR"
TOK0="$(lc "$(one "$(rd "$PAIR" 'token0()(address)')")")"
RR="$(rd "$PAIR" 'getReserves()(uint112,uint112,uint32)')"
R0="$(printf '%s\n' "$RR" | sed -n '1p' | numd)"
R1="$(printf '%s\n' "$RR" | sed -n '2p' | numd)"
# which reserve is which token is a fact about the pair, not about my variable names -- V2 sorts by address
if [ "$(lc "$WLXON")" = "$TOK0" ]; then W_RES="$R0"; U_RES="$R1"; else W_RES="$R1"; U_RES="$R0"; fi
PRICE_T="$(python3 -c 'import sys;from decimal import Decimal as D;print("%.8f" % float((D(sys.argv[2])/D(10)**6)/(D(sys.argv[1])/D(10)**18)))' "$W_RES" "$U_RES")"
note "pair reserves: $(python3 -c 'import sys;print("%.6f" % (int(sys.argv[1])/10**18))' "$W_RES") wLXON + $(python3 -c 'import sys;print("%.6f" % (int(sys.argv[1])/10**6))' "$U_RES") USDC -> $PRICE_T USDC per wLXON"
eq "1" "$(close "$PRICE_T" "$TARGET_PRICE" "$TARGET_PRICE" 0.001)" "the venue's own price IS the ruled price -- the split was not traded away"
eq "1" "$(close "$PRICE_T" "$PLAN_PRICE" "$PLAN_PRICE" 0.001)" "and it matches the price the plan recorded before anything was broadcast"
LPT="$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")"
eq "1" "$(gt "$LPT" 0)" "the timelock holds the LP ($LPT)"
eq "0" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$DEPLOYER")")" "and the hot key holds none"
W_AFTER="$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$DEPLOYER")")"
W_EXPECT="$(python3 -c 'import sys;print(int(sys.argv[1])-int(sys.argv[2]))' "$LIVE_W" "$AMT_W_PLAN")"
eq "$W_EXPECT" "$W_AFTER" "the key now holds 10,000 minus exactly what it put in"

say "6. the promise that has to survive this: the liquidity comes back out"
MINDEL="$(num "$(rd "$STRONG_TL" 'getMinDelay()(uint256)')")"
EXIT_TO="$DEPLOYER"
AP_D="$(cast calldata 'approve(address,uint256)' "$ROUTER" "$LPT")"
EXIT_DL="$(python3 -c 'import sys;print(int(sys.argv[1])+int(sys.argv[2])+604800)' "$(ts)" "$MINDEL")"
MIN_W="$(pct "$AMT_W_PLAN" 99)"; MIN_U="$(pct "$AMT_U_PLAN" 99)"
RM_D="$(cast calldata 'removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)' \
  "$WLXON" "$USDC" "$LPT" "$MIN_W" "$MIN_U" "$EXIT_TO" "$EXIT_DL")"
ARR_T="$(printf '[%s,%s]' "$PAIR" "$ROUTER")"
ARR_D="$(printf '[%s,%s]' "$AP_D" "$RM_D")"
ID="$(one "$(rd "$STRONG_TL" 'hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)' "$ARR_T" "[0,0]" "$ARR_D" "$Z32" "$SALT_A")")"
h="$(send "$DEPLOYER" "$STRONG_TL" 'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)' "$ARR_T" "[0,0]" "$ARR_D" "$Z32" "$SALT_A" "$MINDEL")"
eq "0x1" "$(status "$h")" "scheduleBatch of the exit mined"
GS="$(gask "$h")"
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperationPending(bytes32)(bool)' "$ID")")" "the predicted operation id is pending"
eq "false" "$(one "$(rd "$STRONG_TL" 'isOperationReady(bytes32)(bool)' "$ID")")" "and is NOT ready -- a queued exit cannot be pulled early"
h="$(send "$DEPLOYER" "$STRONG_TL" 'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)' "$ARR_T" "[0,0]" "$ARR_D" "$Z32" "$SALT_A")"
[ -z "$h" ] && ok "the early executeBatch was refused outright" || bad "it executed before the delay -- the custody is decorative ($h)"
eq "$LPT" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")" "and the LP did not move when it was refused"
rpc "$F137" anvil_increaseTime "[$MINDEL]" >/dev/null
rpc "$F137" anvil_mine '["0x1"]' >/dev/null
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperationReady(bytes32)(bool)' "$ID")")" "after the fork's $MINDEL s warp the exit is ready"
h="$(send "$DEPLOYER" "$STRONG_TL" 'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)' "$ARR_T" "[0,0]" "$ARR_D" "$Z32" "$SALT_A")"
eq "0x1" "$(status "$h")" "executeBatch mined -- the LP left custody and both tokens came back"
GE="$(gask "$h")"
W1="$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$EXIT_TO")")"
U1="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$EXIT_TO")")"
eq "1" "$(ge "$W1" "$MIN_W")" "wLXON recovered: $W1 (min $MIN_W)"
eq "1" "$(ge "$U1" "$MIN_U")" "USDC recovered: $U1 (min $MIN_U)"
eq "0" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")" "the timelock holds no LP any more -- custody was a door, not a vault"
note "exit gas measured again here: scheduleBatch $GS + executeBatch $GE"
POL_END="$(result "$F137" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)"
note "POL left in the key at the end of the fork run: $POL_END wei ($(python3 -c 'import sys;print("%.4f" % (int(sys.argv[1])/10**18))' "$POL_END") POL)"
eq "1" "$(gt "$POL_END" 1000000000000000000)" "still more than 1 POL, i.e. the whole loop is affordable from the wallet as it stands"

say "7. production was not touched by measuring any of this"
eq "$ZERO" "$(lc "$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "the live chain still has no wLXON/USDC pair"
eq "$LIVE_NONCE" "$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)" \
   "the live launch-key nonce never moved"
eq "$LIVE_POL" "$(result "$RPC137_SRC" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)" \
   "the live launch key still holds the POL that this run spent only on a fork"
eq "$LIVE_SUP" "$(num "$(rdlive "$WLXON" 'totalSupply()(uint256)')")" "and wLXON supply is unchanged"

printf '\n== PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
printf 'What the remaining POL can and cannot do, measured:\n'
printf '  ·  all %s POL at once buys %s wei USDC on this venue -- %.4f USDC, and leaves nothing to sign with.\n' \
  "$LIVE_POL" "$Q_FULL" "$(python3 -c 'import sys;print(int(sys.argv[1])/10**6)' "$Q_FULL")"
printf '  ·  keeping %s wei for the batch caps buys %s wei -- %.4f USDC -- which at the ruled %s USDC/wLXON\n' \
  "$KEEP_POL" "$Q_KEEP_USDC" "$(python3 -c 'import sys;print(int(sys.argv[1])/10**6)' "$Q_KEEP_USDC")" "$TARGET_PRICE"
printf '     is a %s wLXON pool, not the 10,000 wLXON one. Total depth ~%.2f USDC.\n' \
  "$AMOUNT_WLXON_S" "$(python3 -c 'import sys;print(2*int(sys.argv[1])/10**6)' "$Q_KEEP_USDC")"
printf '  ·  the ruled size (2,356 USDC) costs %s wei POL on this venue -- %.0f POL, %.0fx the wallet.\n' \
  "$Q_RULED_POL" "$(python3 -c 'import sys;print(int(sys.argv[1])/10**18)' "$Q_RULED_POL")" \
  "$(python3 -c 'import sys;print(int(sys.argv[1])/int(sys.argv[2]))' "$Q_RULED_POL" "$LIVE_POL")"
printf '  ·  the loop is mechanically sound: swap, plan, seed, LP to %s, 48 h, both tokens back out.\n' "$STRONG_TL"
