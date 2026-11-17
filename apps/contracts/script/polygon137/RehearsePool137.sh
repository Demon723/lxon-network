#!/usr/bin/env bash
# Prove the whole wLXON/USDC pool route on Polygon -- planner, signer, broadcaster -- on a fork of the
# real chain, with a throwaway key, before anyone is asked to sign a real addLiquidity.
#
#   bash script/polygon137/RehearsePool137.sh
#
# Why this exists separately from the planner's own fork measurement. The planner already mines the three
# steps on a fork to price them, but it does not exercise the two halves that a launch actually runs:
# `SignWlxon137Plan.sh` (keystore + password file, refuses PRIVATE_KEY=, decodes every signature back
# against the plan) and `BroadcastWlxon137Signed.sh` (re-derives the signer before publishing anything).
# A plan that works under anvil's `--unlocked` shortcut but cannot survive its own signer is not
# launch-ready, and only this run can tell those apart.
#
# What is real: everything. The fork is a fork of Polygon mainnet, so the QuickSwap factory, the router,
# both USDC tokens, the v4.1 wLXON and the founder's balance are the deployed contracts in live state.
# What is not real: the key. The provider is a keystore generated under a temp root that this script
# destroys, and the tokens are moved to it by impersonation ON THE FORK only.
#
# The check that makes this worth running is the last one: after broadcasting, the SAME read is taken
# against the live endpoint. If `getPair(wLXON, USDC)` is still 0x0 on mainnet, this rehearsal proved the
# route without creating a pool anyone could trade against -- and a rehearsal that cannot tell whether it
# touched production is not evidence, it is a hope.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

# drpc, not publicnode: an anvil fork of publicnode mines a tx but cannot serve its receipt (403
# "Archive requests require a personal token"), which makes every status assertion in this run read as a
# failure of a transaction that actually succeeded. Measured 2026-10-29 while writing its custody sibling.
RPC137_SRC="${RPC137_SRC:-https://polygon.drpc.org}"
P137="${P137_PORT:-19001}"
F137="http://127.0.0.1:$P137"
WLXON=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
FOUNDER=0x7F715B7f78a7d1d63455f3E2EC1fA31d516f9eF3
WHALE=0x6D9e8dbB2779853db00418D4DcF96F3987CFC9D2           # the WETH/USDC pair: holds far more USDC than we need
AMOUNT_WLXON=500
AMOUNT_USDC=120
ZERO=0x0000000000000000000000000000000000000000
TIMELOCK=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5   # LP lands here; see RehearsePoolCustody137.sh

ROOT="$(mktemp -d /tmp/lxon-pool-plan.XXXXXX)"
KS="$ROOT/keystores"; SECRETS="$ROOT/secrets"; PLAN="$ROOT/plan"; PLAN_NOACK="$ROOT/plan-noack"; PLAN_POOR="$ROOT/plan-poor"
mkdir -p "$KS" "$SECRETS" "$PLAN" "$PLAN_NOACK" "$PLAN_POOR"
A137=""
cleanup(){ [ -n "$A137" ] && kill "$A137" 2>/dev/null; wait 2>/dev/null || true
  case "$ROOT" in /tmp/lxon-pool-plan.*) rm -rf "$ROOT";; esac; }
trap 'cleanup' EXIT

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$*"; }
bad(){ FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$*"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
note(){ printf '  ·    %s\n' "$*"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
j(){ curl -s --max-time 90 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
rpc(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}"; }
# drpc answers empty or half-written under load -- measured here, where an eth_getBalance in the middle of
# a concurrent rehearsal came back as text that json could not parse, and three downstream assertions read
# as a failed funding when the funding had worked. So the JSON unwrap retries, and a parse failure is not
# allowed to look like a zero.
result(){ local out i
  for i in 1 2 3 4 5; do
    out="$(rpc "$1" "$2" "$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result") or "")' 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 2
  done; printf '\n'; return 1; }
# `result` ALREADY unwraps the JSON-RPC envelope and prints the bare value, so a caller that pipes it into
# another `json.load(sys.stdin)["result"]` is parsing a second time and reading nothing. Measured 2026-10-29:
# json.loads("0x5be08ac") fails as "Extra data: line 1 column 2 (char 1)" because "0" alone is valid JSON and
# "x" is the extra data -- so the double parse looks like a broken endpoint, not like a broken reader, and
# every funding assertion downstream read as a chain failure. Convert a `result` hex with hx2i; read an
# OBJECT field with raw_result instead.
jp(){ printf '["%s","%s"]' "$1" "$2"; }
hx2i(){ python3 -c 'import sys;print(int(sys.argv[1],16) if sys.argv[1] else 0)' "$1"; }
raw_result(){ local out i
  for i in 1 2 3 4 5; do
    out="$(rpc "$1" "$2" "$3" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin).get("result")))' 2>/dev/null)"
    [ -n "$out" ] && [ "$out" != "null" ] && { printf '%s\n' "$out"; return 0; }
    sleep 2
  done; printf 'null\n'; return 1; }
rpc_read(){ local ep="$1"; shift; local out i
  for i in 1 2 3; do
    out="$(cast call "$1" "$2" "${@:3}" --rpc-url "$ep" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 2
  done; printf '\n'; return 1; }
rd(){ rpc_read "$F137" "$@"; }
rdlive(){ rpc_read "$RPC137_SRC" "$@"; }
one(){ printf '%s\n' "$1" | awk 'NR==1{print $1}'; }
num(){ printf '%s\n' "$1" | awk 'NR==1{print $1}' | tr -cd '0-9'; }
planfield(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pool"][sys.argv[2]])' "$PLAN/plan.json" "$1"; }
pltx(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txs"][int(sys.argv[2])][sys.argv[3]])' "$PLAN/plan.json" "$1" "$2"; }

say "0. the live chain must still have NO wLXON/USDC pool before this run means anything"
LIVE_HEAD="$(rpc "$RPC137_SRC" eth_blockNumber '[]' | python3 -c 'import sys,json;print(int(json.load(sys.stdin).get("result") or "0x0",16))' 2>/dev/null)"
LIVE_TS="$(rpc "$RPC137_SRC" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
LIVE_PAIR_BEFORE="$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "0x0000000000000000000000000000000000000000" "$(lc "$LIVE_PAIR_BEFORE")" "mainnet has no wLXON/USDC pair yet (this rehearsal must leave that true)"

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
for _ in $(seq 1 90); do
  [ "$(result "$F137" eth_chainId '[]')" = "0x89" ] && { up=1; break; }
  sleep 1
done
[ "$up" = "1" ] || { tail -5 "$ROOT/anvil.log"; bad "the fork did not answer chainId 0x89"; exit 1; }
FORK_HEAD="$(hx2i "$(result "$F137" eth_blockNumber '[]')")"
note "fork head $FORK_HEAD (live head at start: $LIVE_HEAD)"
eq "alive" "$(kill -0 "$A137" 2>/dev/null && echo alive)" \
   "the anvil THIS run started is the process answering port $P137 -- a bind failure would hand the run to a leftover fork"
# The discriminator is the CLOCK, not the block number (Polygon produces a block every ~2 s, so a fresh
# fork legitimately sits a few blocks ahead of a head read seconds earlier). A rehearsal that joined a
# leftover fork would inherit that fork's warped time -- and the custody run's whole point is a +48 h warp.
FORK_TS="$(rpc "$F137" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
GAP="$(python3 -c 'import sys;print(abs(int(sys.argv[1]) - int(sys.argv[2])))' "$FORK_TS" "$LIVE_TS")"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) < 300))' "$GAP")" \
   "and its clock is within 300 s of the live chain's ($GAP s apart) -- a reused fork would carry the previous run's +48 h warp"
eq "$ZERO" "$(lc "$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "and this fork is clean: no wLXON/USDC pair on it"

say "2. a throwaway provider key, generated here and destroyed with this directory"
printf '%s\n' "rehearsal-password-not-a-secret" > "$SECRETS/provider.pw"
umask 077
CAST_PASSWORD="rehearsal-password-not-a-secret" cast wallet new "$KS" provider >"$ROOT/new.log" 2>&1
[ -f "$KS/provider" ] || { bad "no keystore at $KS/provider"; exit 1; }
P="$(cast wallet address --keystore "$KS/provider" --password-file "$SECRETS/provider.pw" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$P" ] && ok "throwaway provider $P" || { bad "could not derive an address from the generated keystore"; exit 1; }
eq "600" "$(stat -f '%Lp' "$KS/provider" 2>/dev/null || stat -c '%a' "$KS/provider" 2>/dev/null)" "keystore is mode 0600 (umask 077 is what does this; cast writes 0644 by default)"

say "3. the refusals come first -- an unfunded provider must not get a plan"
RPC137="$F137" PROVIDER="$P" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" POOL_SELFDEALT_ACK=1 \
  LP_TO="$TIMELOCK" LP_EXIT_UNPROVEN_ACK=1 PLAN_DIR="$PLAN_POOR" PLAN_FORK_PORT=19011 bash script/polygon137/PlanPool137.sh >"$ROOT/poor.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "exit $rc on a provider that holds neither token" || bad "it planned a pool for a wallet holding nothing"
grep -qi "holds 0 wei" "$ROOT/poor.log" && ok "naming the balance it refused on" || bad "refused without saying what was missing: $(tail -2 "$ROOT/poor.log" | head -1)"

say "4. and a split nobody acknowledged must not get a plan either"
RPC137="$F137" PROVIDER="$P" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  LP_TO="$TIMELOCK" LP_EXIT_UNPROVEN_ACK=1 PLAN_DIR="$PLAN_NOACK" PLAN_FORK_PORT=19012 bash script/polygon137/PlanPool137.sh >"$ROOT/noack.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "exit $rc without POOL_SELFDEALT_ACK=1" || bad "it planned a price-setter on default"
grep -qi "self-dealt" "$ROOT/noack.log" && ok "and the refusal states that the split IS the price" || bad "the refusal did not name the price"

say "5. fund the provider ON THE FORK only"
# An impersonated account still needs gas. The founder holds 0 POL on the real chain -- that is one of the
# findings this run exists to work around -- and the WETH/USDC pair is a contract, so neither could sign a
# transfer without POL set on the fork first. Without this the two transfers below die with "insufficient
# funds" and the run reads as a token problem rather than a gas problem.
rpc "$F137" anvil_setBalance "[\"$FOUNDER\",\"$(python3 -c 'print(hex(10**20))')\"]" >/dev/null
rpc "$F137" anvil_setBalance "[\"$WHALE\",\"$(python3 -c 'print(hex(10**20))')\"]" >/dev/null
rpc "$F137" anvil_impersonateAccount "[\"$FOUNDER\"]" >/dev/null
rpc "$F137" anvil_impersonateAccount "[\"$WHALE\"]" >/dev/null
rpc "$F137" anvil_setBalance "[\"$P\",\"$(python3 -c 'print(hex(10**20))')\"]" >/dev/null
eq "$(python3 -c 'print(10**20)')" "$(hx2i "$(result "$F137" eth_getBalance "$(jp "$P" latest)")")" \
   "the provider was given POL on the fork (hex derived in python; bash printf %x wraps above 2**63-1)"
eq "$(python3 -c 'print(10**20)')" "$(hx2i "$(result "$F137" eth_getBalance "$(jp "$FOUNDER" latest)")")" \
   "the impersonated founder was given fork POL so its transfer can pay for gas"
AMT_W="$(python3 -c 'import sys;print(int(sys.argv[1]) * 10**18)' "$AMOUNT_WLXON")"
AMT_U="$(python3 -c 'import sys;print(int(sys.argv[1]) * 10**6)' "$AMOUNT_USDC")"
# The mock can only send what the whale actually holds. This pair carried far more USDC than it does now
# when the fixed 3,000 was written; measured 2026-10-29 the WMATIC/native-USDC pair holds 667.7 USDC,
# so asking it for 3,000 reverted "ERC20: transfer amount exceeds balance" -- a rehearsal bug that reads
# from the outside exactly like a chain problem. Size the mock from the live balance instead of a number.
WHALE_U="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$WHALE")")"
SEND_U="$(python3 -c 'import sys
need, have = int(sys.argv[1]), int(sys.argv[2])
want = min(need * 2, have)
print(want if want >= need else 0)' "$AMT_U" "$WHALE_U")"
[ "$SEND_U" != "0" ] || { bad "whale $WHALE holds only $WHALE_U wei of $USDC, less than the $AMT_U the pool needs -- point WHALE at a bigger holder"; exit 1; }
note "whale $WHALE holds $WHALE_U wei USDC, so the fork mock sends $SEND_U (2x the pool side, capped by its balance)"
h_w="$(cast send --rpc-url "$F137" --unlocked --from "$FOUNDER" "$WLXON" 'transfer(address,uint256)' "$P" "$AMT_W" 2>&1 | tee "$ROOT/w.log" | awk '$1=="transactionHash"{print $2}' | head -1)"
h_u="$(cast send --rpc-url "$F137" --unlocked --from "$WHALE" "$USDC" 'transfer(address,uint256)' "$P" "$SEND_U" 2>&1 | tee "$ROOT/u.log" | awk '$1=="transactionHash"{print $2}' | head -1)"
[ -n "$h_w" ] || bad "no wLXON transfer hash at all: $(head -c 200 "$ROOT/w.log" | tr '\n' ' ')"
[ -n "$h_u" ] || bad "no USDC transfer hash at all: $(head -c 200 "$ROOT/u.log" | tr '\n' ' ')"
recv_status(){ raw_result "$F137" eth_getTransactionReceipt "[\"$1\"]" | python3 -c 'import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: d=None
print((d or {}).get("status","not-mined") if d else "no-receipt")'; }
eq "0x1" "$(recv_status "$h_w")" "the founder's wLXON moved to the provider on the fork"
eq "0x1" "$(recv_status "$h_u")" "USDC moved to the provider on the fork (from the WETH/USDC pair, which holds a lot)"
eq "$AMT_W" "$(one "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$P")")" "the provider holds exactly the wLXON the pool will take"

say "6. plan the pool against the fork"
RPC137="$F137" PROVIDER="$P" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" POOL_SELFDEALT_ACK=1 \
  LP_TO="$TIMELOCK" LP_EXIT_UNPROVEN_ACK=1 PLAN_DIR="$PLAN" PLAN_FORK_PORT=19013 bash script/polygon137/PlanPool137.sh >"$ROOT/plan.log" 2>&1
eq "0" "$?" "the planner exited 0"
if [ ! -s "$PLAN/plan.json" ]; then tail -25 "$ROOT/plan.log"; bad "no plan.json"; exit 1; fi
tail -14 "$ROOT/plan.log"
eq "3" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["txCount"])' "$PLAN/plan.json")" \
   "three transactions: approve wLXON, approve USDC, addLiquidity"
eq "0.24" "$(planfield priceImpliedUsdcPerWlxon)" "the recorded price is the split, 120/500 = 0.24 USDC per wLXON"
eq "SELF-DEALT: this batch's split IS the price. No counterparty, no outside bid, one pool." "$(planfield priceKind)" \
   "and the plan labels it that way instead of leaving it ambiguous"
eq "6" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pool"]["tokenB"]["decimals"])' "$PLAN/plan.json")" \
   "USDC was priced in 6 decimals, read from the token, not assumed"
eq "137" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["chainId"])' "$PLAN/plan.json")" "the plan is for chain 137"
# the run is contiguous from the FIRST planned nonce, and it must also match the live/pending nonce the
# planner read before writing: a plan that starts anywhere else collides with whatever is in flight.
eq "$(python3 -c 'import json,sys;t=json.load(open(sys.argv[1]))["txs"];print(",".join(str(x["nonce"]) for x in t))' "$PLAN/plan.json")" \
   "$(python3 -c 'import sys;print("%d,%d,%d" % (int(sys.argv[1]), int(sys.argv[1])+1, int(sys.argv[1])+2))' "$(pltx 0 nonce)")" \
   "nonces are a contiguous run starting at tx 0's nonce"
eq "$(pltx 0 nonce)" "$(result "$F137" eth_getTransactionCount "$(jp "$P" latest)" | python3 -c 'import sys;print(int(sys.stdin.read().strip() or "0x0",16))')" \
   "and that first nonce is the account's real next nonce on the fork, not a remembered number"

say "7. sign it from a keystore file, and refuse a key on the command line"
out="$(PLAN_DIR="$PLAN" PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000001 bash script/polygon137/SignWlxon137Plan.sh 2>&1)"
printf '%s' "$out" | grep -qi "keystore" && ok "the signer will not take a key from the environment" || bad "it did not refuse PRIVATE_KEY=: $(printf '%s' "$out" | head -2)"
out="$(PLAN_DIR="$PLAN" KEYSTORE="$KS/provider" PASSWORD_FILE="$SECRETS/provider.pw" bash script/polygon137/SignWlxon137Plan.sh 2>&1)"
eq "0" "$?" "the signer exited 0"
eq "3" "$(ls -1 "$PLAN/signed"/*.raw.hex 2>/dev/null | wc -l | tr -d ' ')" "three signed transactions"
i=0
for f in "$PLAN/signed"/*.raw.hex; do
  info="$(cast decode-transaction "$(tr -d '\n' < "$f")" 2>/dev/null | python3 -c 'import sys,json
d=json.load(sys.stdin)
d=json.loads(d) if isinstance(d,str) else d
print("%s|%s|%s|%s|%s" % (d["signer"], int(d["nonce"],16) if str(d["nonce"]).startswith("0x") else d["nonce"], (d.get("to") or "0x"), d["chainId"], int(d["gas"],16) if str(d["gas"]).startswith("0x") else d["gas"]))')"
  sg="$(printf '%s' "$info" | cut -d'|' -f1)"; nn="$(printf '%s' "$info" | cut -d'|' -f2)"
  to="$(printf '%s' "$info" | cut -d'|' -f3)"; ci="$(printf '%s' "$info" | cut -d'|' -f4)"; gg="$(printf '%s' "$info" | cut -d'|' -f5)"
  eq "$(lc "$P")" "$(lc "$sg")" "$(basename "$f"): recovers to the throwaway provider, not to a launch key"
  eq "137" "$(python3 -c 'import sys;v=sys.argv[1];print(int(v,16) if v.startswith("0x") else v)' "$ci")"    "$(basename "$f"): chain 137, so it can never be replayed on 724"
  eq "$(lc "$(pltx "$i" to)")" "$(lc "$to")" "$(basename "$f"): spends at the address the plan names"
  eq "$(pltx "$i" nonce)" "$nn" "$(basename "$f"): pinned to its planned nonce"
  i=$((i + 1))
done

say "8. a plan edited after signing is refused by the broadcaster"
cp "$PLAN/plan.json" "$ROOT/plan.good.json"
python3 - "$PLAN/plan.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
t = d["txs"][-1]
t["data"] = t["data"][:-128] + "0" * 24 + "a" * 40 + t["data"][-64:]   # move the LP recipient, keep the length
json.dump(d, open(p, "w"), indent=1)
PY
out="$(PLAN_DIR="$PLAN" SIGNED_DIR="$PLAN/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"
printf '%s' "$out" | grep -qi "differs from the plan" && ok "the broadcaster refused the edited plan" || bad "it published anyway: $(printf '%s' "$out" | tail -2)"
cp "$ROOT/plan.good.json" "$PLAN/plan.json"
eq "1" "$(python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1]))["txs"][-1]["data"]==json.load(open(sys.argv[2]))["txs"][-1]["data"]))' "$PLAN/plan.json" "$ROOT/plan.good.json")" \
   "and the good plan is restored byte for byte"

say "9. broadcast to the fork"
out="$(PLAN_DIR="$PLAN" SIGNED_DIR="$PLAN/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"
eq "0" "$?" "the broadcaster published all three and waited for each receipt"
printf '%s\n' "$out" | grep -E "^(==>|\s+mined|All )" | head -8

say "10. ask the chain what the pool actually is"
PAIR="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "0" "$(python3 -c 'import sys;print(int(sys.argv[1]=="0x0000000000000000000000000000000000000000"))' "$PAIR")" \
   "the fork now has a wLXON/USDC pair at $PAIR"
RES0="$(one "$(rd "$PAIR" 'getReserves()(uint112,uint112,uint32)')")"
RES1="$(rd "$PAIR" 'getReserves()(uint112,uint112,uint32)' | awk 'NR==2{print $1}')"
TOK0="$(one "$(rd "$PAIR" 'token0()(address)')")"
if [ "$(lc "$TOK0")" = "$(lc "$WLXON")" ]; then RW="$RES0"; RU="$RES1"; else RW="$RES1"; RU="$RES0"; fi
eq "$AMT_W" "$RW" "the pair holds exactly the wLXON the plan said"
eq "$AMT_U" "$RU" "and exactly the USDC"
LP="$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$TIMELOCK")")"
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) > 0))' "$LP")" "LP tokens landed in the custody timelock ($LP)"
eq "0" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$P")")" "and none with the signing key -- broadcasting the route does not leave the position hot"
eq "0" "$(num "$(rd "$USDC" 'allowance(address,address)(uint256)' "$P" "$ROUTER")")" \
   "the USDC approval was consumed by the addLiquidity, so the signed batch cannot be replayed for a second pull"
CHAIN_PRICE="$(python3 -c 'import sys;print("%.6f" % (int(sys.argv[1]) / 1e6 / (int(sys.argv[2]) / 1e18)))' "$RU" "$RW")"
# the plan stores a float (json 0.24) and the chain read is formatted %.6f (0.240000): compare the numbers,
# not the strings, or a correct price fails its own assertion.
eq "$(python3 -c 'import sys;print("%.6f" % float(sys.argv[1]))' "$(planfield priceImpliedUsdcPerWlxon)")" "$CHAIN_PRICE" \
   "the price the CHAIN reports from reserves equals the price the plan recorded -- the number was set by the split, exactly as labelled"

say "11. the check that matters: production was not touched"
LIVE_PAIR_AFTER="$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "$(lc "$LIVE_PAIR_BEFORE")" "$(lc "$LIVE_PAIR_AFTER")" "mainnet still has no wLXON/USDC pair after the whole run"
eq "0" "$(num "$(rdlive "$WLXON" 'balanceOf(address)(uint256)' "$ROUTER")")" "and no wLXON left the live chain's view of the router"

printf '\n== PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
printf 'The pool route works: plan with no key, sign from a keystore file, broadcast with every signature\n'
printf 're-derived, and the price the chain reports is the split the plan recorded. What is still missing is\n'
printf 'not tooling -- it is USDC. No project wallet holds any on 137, and 1,000 wLXON is the whole supply.\n'
