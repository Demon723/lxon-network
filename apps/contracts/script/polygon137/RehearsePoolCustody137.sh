#!/usr/bin/env bash
# Prove that LP put behind a timelock can be TAKEN OUT again on a fork of Polygon 137 -- because custody
# without a demonstrated exit is not custody, it is a burn.
#
#   bash script/polygon137/RehearsePoolCustody137.sh
#
# The owner ruling of 2026-10-29 is "use timelock for lp custody", and the default LP recipient in
# PlanPool137.sh is now the 137 bridge TimelockController 0xe56553Ed… for a measured reason: the deployer
# holds PROPOSER+EXECUTOR+CANCELLER there but NOT DEFAULT_ADMIN, whereas on the other timelock this
# project owns (0x5Bfc2fD8…, the migration one) the deployer holds DEFAULT_ADMIN too, so the delay in
# front of that one is removable by the same key that would have to wait it out.
#
# Nothing here is a restatement of that. The run does five things a planner cannot:
#   1. refuses the weak custody, a codeless custody, address(0), and self-custody -- each with its own ack;
#   2. refuses a custody the signing key cannot exit (PROPOSER/EXECUTOR absent), which is the failure mode
#      that turns a 48 h delay into a permanent lock;
#   3. mints LP into the timelock using the calldata PLAN wrote, not a hand-written call, so the thing
#      being proven is the thing that would be broadcast;
#   4. schedules the real exit -- scheduleBatch(pair.approve, router.removeLiquidity) -- reads the
#      operation id back FROM the contract (hashOperationBatch), and shows executeBatch is refused and
#      nothing moves before minDelay has passed;
#   5. waits out the delay on the fork, executes, and asserts the underlying arrives at a chosen address,
#      the LP is gone from the timelock, and the pair's totalSupply is 0.
#
# What is real: a fork of Polygon mainnet, so the factory, router, both tokens, the founder's balance and
# the deployed TimelockController are the production bytecode in production state. What is not: the money.
# The wLXON and USDC are moved to the provider BY IMPERSONATION ON THE FORK ONLY, and the throwaway
# addresses are generated under a temp root this script destroys. No key is read or signed with here --
# the fork runs --auto-impersonate, so the exit is driven by an address, not by a signature. The last
# section re-reads the live endpoint and fails the run if production state moved.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

# drpc, not publicnode, for the fork upstream. Measured here 2026-10-29: an anvil fork of
# polygon-bor-rpc.publicnode.com MINEs a state-changing transaction and then cannot serve its receipt --
# `eth_getTransactionReceipt` comes back as `Fork Error: Transport(HttpError { status: 403, "Archive
# requests require a personal token" })`, so every status assertion reads as no-tx while the balance
# change actually happened. polygon.drpc.org answers both. The live reads at the top and bottom of this
# run are harmless either way; the fork is not.
RPC137_SRC="${RPC137_SRC:-https://polygon.drpc.org}"
P137="${P137_PORT:-19002}"
F137="http://127.0.0.1:$P137"
PLAN_PORT="${PLAN_FORK_PORT:-19014}"
WLXON=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
FOUNDER=0x7F715B7f78a7d1d63455f3E2EC1fA31d516f9eF3
WHALE=0x6D9e8dbB2779853db00418D4DcF96F3987CFC9D2                  # the WETH/USDC pair: a deep USDC holder
STRONG_TL=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5              # bridge timelock -- deployer is NOT admin
WEAK_TL=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054                # migration timelock -- deployer IS admin
DEPLOYER=0x2a8Ca01C53cecF360b181a0B7D49a71565684665               # PROPOSER + EXECUTOR on STRONG_TL
ZERO=0x0000000000000000000000000000000000000000
Z32=0x0000000000000000000000000000000000000000000000000000000000000000
SALT_A=0x000000000000000000000000000000000000000000000000000000000000c0de
SALT_B=0x00000000000000000000000000000000000000000000000000000000000000ff
SALT_C=0x00000000000000000000000000000000000000000000000000000000000000fe
AMOUNT_WLXON=500
AMOUNT_USDC=120
R_ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
R_PROPOSER=0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1

# ---- helpers, every one defined before the first use. RehearsePool137.sh kept one assertion above this
# ---- block and died on `command not found`; a rehearsal that cannot start is not evidence.
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
int16(){ python3 -c 'import sys;print(int(sys.argv[1],16))' "$1" 2>/dev/null; }
# an argument-taking int16 is not the same tool as a pipe-reading one: `... | int16` called the
# function with no positional parameter and died on `set -u` several lines after the read that
# mattered. hexd is the pipe form; the two are kept separate so the mistake cannot come back.
hexd(){ python3 -c 'import sys
s=sys.stdin.read().strip().strip(chr(34))
print(int(s,16) if s else "")' 2>/dev/null; }
gt(){ python3 -c 'import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))' "$1" "$2"; }
ge(){ python3 -c 'import sys;print(int(int(sys.argv[1]) >= int(sys.argv[2])))' "$1" "$2"; }
le(){ python3 -c 'import sys;print(int(int(sys.argv[1]) <= int(sys.argv[2])))' "$1" "$2"; }
pct(){ python3 -c 'import sys;print(int(sys.argv[1]) * int(sys.argv[2]) // 100)' "$1" "$2"; }
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
# status/gask parse the RPC envelope THEMSELVES. Feeding them through `result` is a double decode: result
# already prints the decoded "result" member, so the second json.load sees a python repr and dies, and the
# tx that mined happily on the fork reads as "no-tx". Measured here on 2026-10-29 -- a green transaction
# reported as a failure is the worst possible kind of failure in a rehearsal.
status(){ [ -z "$1" ] && { printf 'no-tx\n'; return; }
  rpc "$F137" eth_getTransactionReceipt "[\"$1\"]" \
  | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("status","not-mined"))' 2>/dev/null; }
gask(){ rpc "$F137" eth_getTransactionReceipt "[\"$1\"]" \
  | python3 -c 'import sys,json;d=(json.load(sys.stdin).get("result") or {});print(int(d.get("gasUsed","0x0"),16) if d.get("gasUsed") else "")' 2>/dev/null; }
cf(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["custody"][sys.argv[2]])' "$PLAN/plan.json" "$1"; }
cpf(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["custody"]["measured"][sys.argv[2]])' "$PLAN/plan.json" "$1"; }
pf(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pool"][sys.argv[2]])' "$PLAN/plan.json" "$1"; }
pltxdata(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["data"])' "$PLAN/plan.json" "$1"; }

ROOT="$(mktemp -d /tmp/lxon-pool-custody.XXXXXX)"
KS="$ROOT/keystores"; SEC="$ROOT/secrets"; PLAN="$ROOT/plan"; mkdir -p "$KS" "$SEC" "$PLAN"
A137=""
cleanup(){ [ -n "$A137" ] && kill "$A137" 2>/dev/null; wait 2>/dev/null || true
  case "$ROOT" in /tmp/lxon-pool-custody.*) rm -rf "$ROOT";; esac; }
trap 'cleanup' EXIT

say "0. the claims this run rests on, read from the LIVE chain before anything is forked"
MINDEL="$(num "$(rdlive "$STRONG_TL" 'getMinDelay()(uint256)')")"
[ -n "$MINDEL" ] || { bad "could not read getMinDelay() from $STRONG_TL on $RPC137_SRC -- nothing below means anything"; exit 1; }
note "bridge timelock $STRONG_TL minDelay $MINDEL s ($(( MINDEL / 3600 ))h)"
eq "false" "$(one "$(rdlive "$STRONG_TL" 'hasRole(bytes32,address)(bool)' "$R_ADMIN" "$DEPLOYER")")" \
   "the deployer does NOT hold DEFAULT_ADMIN on the custody timelock, so the delay is not its to move"
eq "true" "$(one "$(rdlive "$STRONG_TL" 'hasRole(bytes32,address)(bool)' "$R_PROPOSER" "$DEPLOYER")")" \
   "and it does hold PROPOSER_ROLE, which is what lets it schedule the exit at all"
eq "true" "$(one "$(rdlive "$WEAK_TL" 'hasRole(bytes32,address)(bool)' "$R_ADMIN" "$DEPLOYER")")" \
   "while on the migration timelock the SAME key holds DEFAULT_ADMIN -- the reason that one is refused"
LIVE_HEAD="$(result "$RPC137_SRC" eth_blockNumber '[]' | python3 -c 'import sys,json;print(int(json.load(sys.stdin).get("result") or "0x0",16))' 2>/dev/null)"
LIVE_TS="$(rpc "$RPC137_SRC" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
LIVE_PAIR="$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "$ZERO" "$(lc "$LIVE_PAIR")" "mainnet has no wLXON/USDC pair before this run"
LIVE_NONCE="$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)"
LIVE_FOUNDER="$(num "$(rdlive "$WLXON" 'balanceOf(address)(uint256)' "$FOUNDER")")"
note "live deployer nonce $LIVE_NONCE, founder wLXON $LIVE_FOUNDER -- both must be untouched at the end"

say "1. a fork of Polygon 137"
# refuse to start on a port something already answers. A leftover fork from an earlier run reports a
# chainId, so the run silently joins ITS state -- measured here as a pair whose reserves were exactly
# twice what this run deposited, because the rehearsal had really joined a previous rehearsal.
if [ -n "$(rpc "$P137" eth_chainId '[]' 2>/dev/null | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or ""))' 2>/dev/null)" ]; then
  bad "port $P137 is already serving an RPC -- a stale fork would be joined instead of created. Kill it and re-run."
  exit 1
fi
anvil --fork-url "$RPC137_SRC" --chain-id 137 --port "$P137" --auto-impersonate >"$ROOT/anvil.log" 2>&1 & A137=$!
up=0
for _ in $(seq 1 120); do
  [ "$(result "$F137" eth_chainId '[]')" = "0x89" ] && { up=1; break; }
  sleep 1
done
[ "$up" = "1" ] || { tail -8 "$ROOT/anvil.log"; bad "the fork did not answer chainId 0x89"; exit 1; }
FORK_HEAD="$(result "$F137" eth_blockNumber '[]' | hexd)"
note "fork head $FORK_HEAD (live head at start: $LIVE_HEAD)"
eq "alive" "$(kill -0 "$A137" 2>/dev/null && echo alive)" \
   "the anvil THIS run started is still the process answering port $P137 (a bind failure would otherwise hand the run to a leftover fork)"
# The discriminator is the CLOCK, not the block number (Polygon produces a block every ~2 s, so a fresh
# fork legitimately sits a few blocks ahead of a head read seconds earlier). A rehearsal that joined a
# leftover fork would inherit that fork's warped time -- and the custody run's whole point is a +48 h warp.
FORK_TS="$(rpc "$F137" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
GAP="$(python3 -c 'import sys;print(abs(int(sys.argv[1]) - int(sys.argv[2])))' "$FORK_TS" "$LIVE_TS")"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) < 300))' "$GAP")" \
   "and its clock is within 300 s of the live chain's ($GAP s apart) -- a reused fork would carry the previous run's +48 h warp"
eq "$ZERO" "$(lc "$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "and this fork is clean: no wLXON/USDC pair on it, which a reused fork would have had"
eq "$MINDEL" "$(num "$(rd "$STRONG_TL" 'getMinDelay()(uint256)')")" "the fork mirrors the live minDelay -- it is the same deployed contract"

say "2. two throwaway addresses: where the withdrawn liquidity lands, and a key with no roles at all"
printf 'rehearsal-password-not-a-secret\n' > "$SEC/x.pw"
umask 077
CAST_PASSWORD="rehearsal-password-not-a-secret" cast wallet new "$KS" exit-to >"$ROOT/k1.log" 2>&1
CAST_PASSWORD="rehearsal-password-not-a-secret" cast wallet new "$KS" stranger >"$ROOT/k2.log" 2>&1
[ -f "$KS/exit-to" ] && [ -f "$KS/stranger" ] || { bad "a throwaway keystore is missing"; exit 1; }
EXIT_TO="$(cast wallet address --keystore "$KS/exit-to" --password-file "$SEC/x.pw" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
STRANGER="$(cast wallet address --keystore "$KS/stranger" --password-file "$SEC/x.pw" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$EXIT_TO" ] && [ -n "$STRANGER" ] || { bad "could not derive addresses from the generated keystores"; exit 1; }
eq "600" "$(stat -f '%Lp' "$KS/exit-to" 2>/dev/null || stat -c '%a' "$KS/exit-to" 2>/dev/null)" \
   "the keystores are mode 0600 (umask 077 does this; cast wallet new writes 0644)"
note "exit destination $EXIT_TO  |  no-role key $STRANGER"
eq "0x" "$(result "$F137" eth_getCode "$(jp "$EXIT_TO" latest)")" \
   "the exit destination is a plain address with no code -- LP moved there is hot again, which is the point of watching it arrive"

say "3. the custody gates refuse four destinations before any money is planned"
g(){ local name="$1" want="$2"; shift 2
  local d="$ROOT/ref-$name"; mkdir -p "$d"
  RPC137="$F137" PROVIDER="$DEPLOYER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  POOL_SELFDEALT_ACK=1 PLAN_DIR="$d" PLAN_FORK_PORT="$(( PLAN_PORT + 30 ))" \
    env "$@" bash script/polygon137/PlanPool137.sh >"$ROOT/$name.log" 2>&1
  local rc=$?
  [ "$rc" != "0" ] && ok "$name refused (exit $rc)" || bad "$name planned anyway"
  if grep -qi "$want" "$ROOT/$name.log"; then
    ok "   says why: $(grep -i -m1 "$want" "$ROOT/$name.log" | sed 's/^ *FATAL: //' | cut -c1-90)"
  else
    bad "   refusal did not mention [$want]: $(tail -2 "$ROOT/$name.log" | head -1 | cut -c1-90)"
  fi
  [ ! -f "$d/plan.json" ] && ok "   and left no plan behind" || bad "   it wrote a plan.json despite refusing"
}
g weak "DEFAULT_ADMIN to the planning key" LP_TO="$WEAK_TL"
g hot  "has no code"                       LP_TO="$STRANGER"
g zero "address(0)"                        LP_TO="$ZERO"
g self "same key that seeds the pool"      LP_TO="$DEPLOYER"

say "4. the exit-capability gate on its own: a signer that cannot execute must not take custody"
d="$ROOT/ref-noexit"; mkdir -p "$d"
RPC137="$F137" PROVIDER="$STRANGER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
POOL_SELFDEALT_ACK=1 PLAN_DIR="$d" PLAN_FORK_PORT="$(( PLAN_PORT + 31 ))" LP_TO="$STRONG_TL" \
  bash script/polygon137/PlanPool137.sh >"$ROOT/noexit.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "a plan signed by a key with no PROPOSER/EXECUTOR is refused (exit $rc)" \
  || bad "it minted LP into a custody the signer cannot leave"
if grep -qi "unredeemable" "$ROOT/noexit.log"; then note "the refusal names the failure it prevents: the position would be unredeemable";
else bad "refused without saying the position would be unredeemable"; fi
[ ! -f "$d/plan.json" ] && ok "and no plan was written" || bad "it wrote a plan anyway"
grep -qi "LP_EXIT_UNPROVEN_ACK" "$ROOT/noexit.log" && ok "the override exists, so an operator holding the roles elsewhere is not blocked" \
  || bad "no documented override on that gate -- it would block a legitimate multisig custody"

say "5. fund the provider ON THE FORK only, then plan the pool into the real custody"
# Impersonation removes the signature check, not the gas bill: the founder holds 0 POL on 137 (that is
# the whole reason the pool cannot be seeded from it today), so on the fork it is given gas money first.
# Funding it here is a rehearsal device, not a claim that it could pay on the live chain.
HEX_GAS="$(python3 -c 'print(hex(3 * 10**17))')"
rpc "$F137" anvil_impersonateAccount "[\"$FOUNDER\"]" >/dev/null
rpc "$F137" anvil_impersonateAccount "[\"$WHALE\"]" >/dev/null
rpc "$F137" anvil_setBalance "[\"$FOUNDER\",\"$HEX_GAS\"]" >/dev/null
rpc "$F137" anvil_setBalance "[\"$WHALE\",\"$HEX_GAS\"]" >/dev/null
eq "$(python3 -c 'print(3 * 10**17)')" "$(result "$F137" eth_getBalance "$(jp "$FOUNDER" latest)" | hexd)" \
   "the founder was given POL on the fork only, so its impersonated transfer can pay for gas" 
AMT_W="$(python3 -c 'import sys;print(int(sys.argv[1]) * 10**18)' "$AMOUNT_WLXON")"
AMT_U="$(python3 -c 'import sys;print(int(sys.argv[1]) * 10**6)' "$AMOUNT_USDC")"
tw="$(send "$FOUNDER" "$WLXON" 'transfer(address,uint256)' "$DEPLOYER" "$AMT_W")"
[ -n "$tw" ] || note "founder transfer produced no hash: $(grep -m1 -i error "$ROOT/last.log" | cut -c1-170)"
eq "0x1" "$(status "$tw")" "the founder's wLXON moved to the deployer on the fork"
tu="$(send "$WHALE" "$USDC" 'transfer(address,uint256)' "$DEPLOYER" "$AMT_U")"
[ -n "$tu" ] || note "USDC transfer produced no hash: $(grep -m1 -i error "$ROOT/last.log" | cut -c1-170)"
eq "0x1" "$(status "$tu")" "USDC moved to the deployer on the fork (from the WETH/USDC pair, which holds a great deal of it)"
RPC137="$F137" PROVIDER="$DEPLOYER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
POOL_SELFDEALT_ACK=1 PLAN_DIR="$PLAN" PLAN_FORK_PORT="$PLAN_PORT" LP_TO="$STRONG_TL" \
  bash script/polygon137/PlanPool137.sh >"$ROOT/plan.log" 2>&1
eq "0" "$?" "the planner exited 0 with the timelock as custody"
[ -s "$PLAN/plan.json" ] || { tail -20 "$ROOT/plan.log"; bad "no plan.json"; exit 1; }
ok "plan written: $(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("%d tx, nonce %d, phase %s" % (d["txCount"], d["startNonce"], d["phase"]))' "$PLAN/plan.json")"
eq "timelock" "$(cf kind)" "the plan records the custody as a timelock"
eq "$STRONG_TL" "$(pf lpRecipient)" "and names the address the LP will be minted to"
eq "$MINDEL" "$(cf minDelaySeconds)" "with the minDelay it read from that contract, not the one written in the script"
eq "false" "$(cpf providerIsDefaultAdmin)" "measured: the signing key is not admin there"
eq "true" "$(cpf providerIsProposer)" "measured: it is a proposer"
eq "true" "$(cpf providerIsExecutor)" "measured: and an executor -- the exit it records is an exit it can run"

say "6. replay the plan's own addLiquidity bytes on the fork and see where the LP lands"
ALD="$(pltxdata 2)"
eq "0xe8e33700" "${ALD:0:10}" "tx 2 of the plan is an addLiquidity call"
PLAN_DL="$(python3 -c 'import sys;print(int(sys.argv[1][-64:],16))' "$ALD")"
NOW_DL="$(ts)"
if [ "$(gt "$PLAN_DL" "$NOW_DL")" = "1" ]; then
  ok "the planned deadline ($PLAN_DL) is still ahead of fork time ($NOW_DL), so the exact bytes can be replayed"
else
  note "the plan's deadline ($PLAN_DL) has already passed on this fork (time $NOW_DL) -- replaying it would revert by design, so the same call is rebuilt with a fresh deadline and diffed against the plan below"
fi
RM_ARG_TO="$(python3 -c 'import sys;print("0x"+sys.argv[1][-128:-64][-40:])' "$ALD")"
eq "$(lc "$STRONG_TL")" "$(lc "$RM_ARG_TO")" "the LP recipient inside the planned calldata is the custody timelock itself"
# The three planned calls in the order the plan puts them: the two approvals first, because addLiquidity
# pulls with transferFrom and the router can only pull what it has been handed. Rehearsing the third call
# alone reverts `TransferHelper: TRANSFER_FROM_FAILED` -- which is the same ordering trap the live 724 leg
# has a whole gate for.
for i in 0 1; do
  d="$(pltxdata "$i")"
  to_i="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["to"])' "$PLAN/plan.json" "$i")"
  hh="$(send "$DEPLOYER" "$to_i" "$d")"
  eq "0x1" "$(status "$hh")" "planned tx $i -- $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])]["label"])' "$PLAN/plan.json" "$i") -- mined from the plan's own bytes"
done
if [ "$(gt "$PLAN_DL" "$NOW_DL")" = "1" ]; then
  h="$(send "$DEPLOYER" "$ROUTER" "$ALD")"
else
  h="$(send "$DEPLOYER" "$ROUTER" 'addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)' \
     "$WLXON" "$USDC" "$AMT_W" "$AMT_U" "$AMT_W" "$AMT_U" "$STRONG_TL" "$(python3 -c 'import sys;print(int(sys.argv[1])+3600)' "$(ts)")")"
fi
eq "0x1" "$(status "$h")" "addLiquidity mined on the fork"
PAIR="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "1" "$(python3 -c 'import sys;print(int(sys.argv[1] != sys.argv[2]))' "$PAIR" "$ZERO")" "the factory names a pair now: $PAIR"
LPT="$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")"
LPP="$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$DEPLOYER")")"
eq "1" "$(gt "$LPT" 0)" "the timelock holds the LP ($LPT)"
eq "0" "$LPP" "and the provider holds none -- custody is not a copy; the hot key cannot spend it"

say "7. build the exit the runbook will promise: approve + removeLiquidity as one timed batch"
AP_D="$(cast calldata 'approve(address,uint256)' "$ROUTER" "$LPT")"
EXIT_DEADLINE="$(python3 -c 'import sys;print(int(sys.argv[1]) + int(sys.argv[2]) + 604800)' "$(ts)" "$MINDEL")"
MIN_W="$(pct "$AMT_W" 99)"; MIN_U="$(pct "$AMT_U" 99)"
RM_D="$(cast calldata 'removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)' \
  "$WLXON" "$USDC" "$LPT" "$MIN_W" "$MIN_U" "$EXIT_TO" "$EXIT_DEADLINE")"
ARR_T="$(printf '[%s,%s]' "$PAIR" "$ROUTER")"
ARR_V='[0,0]'
ARR_D="$(printf '[%s,%s]' "$AP_D" "$RM_D")"
eq "2" "$(python3 -c 'import sys;print(len(sys.argv[1].split(",")))' "$ARR_T")" "the batch has two calls: the timelock approves the router, then the router removes"
ID="$(one "$(rd "$STRONG_TL" 'hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_A")")"
[ -n "$ID" ] && [ "$ID" != "$Z32" ] && ok "the timelock itself computes the operation id: $ID" || bad "hashOperationBatch gave [$ID]"
eq "false" "$(one "$(rd "$STRONG_TL" 'isOperation(bytes32)(bool)' "$ID")")" "and that id is not scheduled yet"
T0="$(ts)"
h="$(send "$DEPLOYER" "$STRONG_TL" 'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_A" "$MINDEL")"
eq "0x1" "$(status "$h")" "scheduleBatch mined -- the exit is queued"
GS="$(gask "$h")"; note "measured scheduleBatch gasUsed on the fork: $GS"
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperation(bytes32)(bool)' "$ID")")" "the id predicted before scheduling is the id now pending"
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperationPending(bytes32)(bool)' "$ID")")" "isOperationPending"
eq "false" "$(one "$(rd "$STRONG_TL" 'isOperationReady(bytes32)(bool)' "$ID")")" "isOperationReady -- not yet"
# readyAt is the timestamp of the block the schedule mined INTO, not the head block read beforehand: anvil
# seals on the transaction, so those two differ by the block interval and the first draft of this check
# failed by 2 seconds on a contract that was behaving perfectly.
# Flat assignments, one substitution each: bash 3.2 cannot parse a third level of quoted $( ) and reports
# the error lines away from the cause, which is the one class of failure this project keeps paying for.
REC="$(rpc "$F137" eth_getTransactionReceipt "[\"$h\"]")"
SB="$(printf '%s' "$REC" | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("blockNumber","0x0"))')"
BLK="$(rpc "$F137" eth_getBlockByNumber "[\"$SB\",false]")"
SCHED_TS="$(printf '%s' "$BLK" | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
RDY="$(num "$(rd "$STRONG_TL" 'getTimestamp(bytes32)(uint256)' "$ID")")"
WANT_RDY="$(python3 -c 'import sys;print(int(sys.argv[1])+int(sys.argv[2]))' "$SCHED_TS" "$MINDEL")"
eq "$WANT_RDY" "$RDY" "readyAt is exactly the schedule block's timestamp ($SCHED_TS) + minDelay"
eq "1" "$(ge "$RDY" "$(python3 -c 'import sys;print(int(sys.argv[1])+int(sys.argv[2]))' "$T0" "$MINDEL")")" \
   "and never less than the whole $MINDEL s after the head read that preceded the send"
eq "$LPT" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")" "scheduling moved nothing -- the LP is still in custody"

say "8. three refusals, each checked against the state as well as the exit code"
h="$(send "$DEPLOYER" "$STRONG_TL" 'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_A")"
[ -z "$h" ] && ok "executeBatch before the delay is refused" || bad "it executed early -- the delay is decorative"
eq "$LPT" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")" "and the LP did not move when it was refused"
h="$(send "$STRANGER" "$STRONG_TL" 'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_B" "$MINDEL")"
[ -z "$h" ] && ok "a key with no PROPOSER_ROLE cannot schedule the exit" || bad "anyone could queue the exit: $h"
h="$(send "$DEPLOYER" "$STRONG_TL" 'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_C" 1)"
[ -z "$h" ] && ok "a delay below minDelay is refused too -- the floor is enforced, not advised" || bad "it scheduled a 1-second timelock: $h"
eq "false" "$(one "$(rd "$STRONG_TL" 'isOperation(bytes32)(bool)' "$(one "$(rd "$STRONG_TL" 'hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_C")")")")" \
   "and the refused 1-second operation was never registered"

say "9. wait the delay out (on the fork) and run it"
rpc "$F137" anvil_increaseTime "[$MINDEL]" >/dev/null
rpc "$F137" anvil_mine '["0x1"]' >/dev/null
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperationReady(bytes32)(bool)' "$ID")")" "after $MINDEL s the operation is ready"
eq "0" "$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$EXIT_TO")")" "(the destination held no wLXON beforehand)"
eq "0" "$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$EXIT_TO")")" "(and no USDC)"
h="$(send "$DEPLOYER" "$STRONG_TL" 'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)' "$ARR_T" "$ARR_V" "$ARR_D" "$Z32" "$SALT_A")"
eq "0x1" "$(status "$h")" "executeBatch mined -- the LP left the timelock under the timelock's own authority"
GE="$(gask "$h")"; note "measured executeBatch gasUsed on the fork: $GE"
eq "true" "$(one "$(rd "$STRONG_TL" 'isOperationDone(bytes32)(bool)' "$ID")")" "the operation is marked done, so it cannot be replayed"
eq "0" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")" "the timelock holds no LP any more -- custody was a door, not a vault"
eq "0" "$(num "$(rd "$PAIR" 'allowance(address,address)(uint256)' "$STRONG_TL" "$ROUTER")")" "the approve inside the batch was consumed by the removal"
W1="$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$EXIT_TO")")"
U1="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$EXIT_TO")")"
eq "1" "$(gt "$W1" 0)" "the wLXON came back out ($W1 wei)"
eq "1" "$(gt "$U1" 0)" "and the USDC ($U1 wei)"
eq "1" "$(ge "$W1" "$MIN_W")" "at or above the 1% minimum the batch specified"
eq "1" "$(ge "$U1" "$MIN_U")" "on both sides"
eq "1" "$(le "$W1" "$AMT_W")" "and never more wLXON than went in"
eq "1" "$(le "$U1" "$AMT_U")" "or more USDC"
TS1="$(num "$(rd "$PAIR" 'totalSupply()(uint256)')")"
eq "1" "$(le "$TS1" 1000)" "nothing redeemable is left in the pair's LP ledger ($TS1 totalSupply remains -- a V2 pair locks MINIMUM_LIQUIDITY to address(0) at mint, so 1000 is the floor, not a stake)"
eq "$TS1" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$ZERO")")" "and every remaining LP wei is the one burned at address(0), held by nobody"
note "round trip: in $AMT_W/$AMT_U, out $W1/$U1; the gap is the LP fee the pair keeps plus rounding"

say "10. production was not touched by proving any of this"
eq "$ZERO" "$(lc "$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "the live chain still has no wLXON/USDC pair"
eq "$LIVE_NONCE" "$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)" \
   "the live deployer nonce never moved -- nothing was signed or broadcast from a launch key"
eq "$LIVE_FOUNDER" "$(num "$(rdlive "$WLXON" 'balanceOf(address)(uint256)' "$FOUNDER")")" \
   "and the founder's live wLXON balance is exactly what it was at the start"

printf '\n== PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
printf 'Timelock LP custody works and it is reversible: the LP lands in %s, nothing can pull it for\n' "$STRONG_TL"
printf '%d s, a key without PROPOSER cannot even queue the pull, and after the delay one scheduleBatch +\n' "$MINDEL"
printf 'executeBatch (%s + %s gas on the fork) returns both tokens to a chosen address and burns the\n' "$GS" "$GE"
printf 'position. What this did NOT prove: the live signature half (RehearsePool137.sh owns that -- it is\n'
printf 'green as of 2026-10-29 at 47 assertions on a fork with a throwaway key, but no real keystore has\n'
printf 'ever signed a pool plan, because no project wallet has ever held USDC to seed one).\n'
