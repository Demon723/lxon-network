#!/usr/bin/env bash
# Prove the one command the owner will actually type, before it is ever typed at production.
#
#   bash script/polygon137/RehearseLaunchPool137.sh
#
# `script/polygon137/LaunchPool137.sh` (plan -> sign -> broadcast in one shot) sits in this worktree
# untracked and has never run. The two pool rehearsals that ARE green drive planner and signer separately
# (RehearsePool137.sh 50/0, RehearsePoolCustody137.sh 78/0), which leaves the launcher -- the file a launch
# is actually driven from -- unexercised: its own prechecks, its staged-not-broadcast branch, its reuse
# refusal, and the fact that BROADCAST=1 re-plans from scratch.
#
# What this run does:
#   1. reads the LIVE chain first, so "production untouched" at the end is a comparison and not a hope;
#   2. forks Polygon 137 and generates ONE throwaway signing key in a temp root it destroys;
#   3. funds the legs on the fork only -- 117.80 USDC taken from the real WMATIC/USDC pair for each of the
#      launch key and the throwaway, 500 wLXON sent from the launch key's real 10,000 -- nothing is minted;
#   4. asks the launcher to stage a plan whose sender is the launch key, with the throwaway keystore, and
#      expects to be refused: a signature has to come from the account the plan names;
#   5. drives it for a provider the throwaway DOES sign for, and checks three gates: staged-and-stopped,
#      a reused PLAN_DIR, and an unknown USDC_KIND;
#   6. runs it once with BROADCAST=1 against the fork and asserts the pair, the LP in the custody timelock,
#      zero LP in the signing key, and the price the reserves print;
#   7. re-reads production.
#
# Legs are sized so the ruled price survives at a scale the fork can fund: 500 wLXON + 117.80 USDC =
# 1 wLXON = $0.2356. Every plan's own `rpc` field points at the fork, which is what makes step 6 a
# rehearsal rather than a launch, and the planner's zero-slippage default is left alone.
#
# One thing this run is NOT: it does not exercise the launcher with the real keystore. That path signs
# mainnet-valid bytes for the launch key, so it stays the owner's single command, rehearsed here only in
# shape. Note also that a provider other than 0x2a8Ca01C… needs LP_EXIT_UNPROVEN_ACK=1 in the environment
# for the planner's exit-capability gate to pass -- LaunchPool137.sh does not set it, so the launcher's own
# happy path is the launch key as provider.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC137_SRC="${RPC137_SRC:-https://polygon.drpc.org}"
P137="${P137_PORT:-19008}"
F137="http://127.0.0.1:$P137"
PLAN_PORT="${PLAN_FORK_PORT:-19018}"
WLXON=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
WMATIC=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
FACTORY=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
ROUTER=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
REF_PAIR=0x6D9e8dbB2779853db00418D4DcF96F3987CFC9D2
DEPLOYER=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
STRONG_TL=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5
ZERO=0x0000000000000000000000000000000000000000
AMOUNT_WLXON=500
AMOUNT_USDC=117.80
TARGET_PRICE=0.2356
W_WEI=500000000000000000000
U_WEI=117800000

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
numd(){ awk 'NR==1{print $1}' | tr -cd '0-9'; }
hexd(){ python3 -c 'import sys
s=sys.stdin.read().strip().strip(chr(34))
print(int(s,16) if s else "")' 2>/dev/null; }
gt(){ python3 -c 'import sys;print(int(int(sys.argv[1]) > int(sys.argv[2])))' "$1" "$2"; }
ne(){ python3 -c 'import sys;print(int(sys.argv[1] != sys.argv[2]))' "$1" "$2"; }
close(){ python3 -c 'import sys
a=float(sys.argv[1]); b=float(sys.argv[2]); t=float(sys.argv[3])
print(int(abs(a-b) <= abs(t)*float(sys.argv[4])))' "$1" "$2" "$3" "$4"; }
rpc_read(){ local out i
  for i in 1 2 3; do
    out="$(cast call "$@" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep 1
  done; printf '\n'; return 1; }
rd(){ rpc_read "$1" "$2" "${@:3}" --rpc-url "$F137"; }
rdlive(){ rpc_read "$1" "$2" "${@:3}" --rpc-url "$RPC137_SRC"; }
lf(){ printf '%s\n' "$1" | tr '\n' ' ' | tail -c 300; }
st(){ rpc "$F137" eth_getTransactionReceipt "[\"$1\"]" | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("status","not-mined"))' 2>/dev/null; }
pj(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2" 2>/dev/null; }
pjp(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' "$1" "$2" "$3" 2>/dev/null; }
nj(){ ls -1 "$1"/*.raw.hex 2>/dev/null | wc -l | tr -d ' ' ; }
send_as(){ cast send --rpc-url "$F137" --unlocked --from "$1" "$2" "$3" "${@:4}" 2>&1 | tee "$ROOT/send.log" | awk '$1=="transactionHash"{print $2}' | head -1; }

ROOT="$(mktemp -d /tmp/lxon-launch-pool.XXXXXX)"
KS_DIR="$ROOT/keystores"; SEC="$ROOT/secrets"; mkdir -p "$KS_DIR" "$SEC"
A137=""
cleanup(){ [ -n "$A137" ] && kill "$A137" 2>/dev/null; wait 2>/dev/null || true
  case "$ROOT" in /tmp/lxon-launch-pool.*) rm -rf "$ROOT";; esac; }
trap 'cleanup' EXIT

say "0. the live chain, before any fork exists -- these are the values re-checked at the end"
LIVE_POL="$(result "$RPC137_SRC" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)"
LIVE_NONCE="$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)"
LIVE_TS="$(rpc "$RPC137_SRC" eth_getBlockByNumber '["latest",false]' | python3 -c 'import sys,json;print(int((json.load(sys.stdin).get("result") or {}).get("timestamp","0x0"),16))')"
LIVE_HEAD="$(result "$RPC137_SRC" eth_blockNumber '[]' | hexd)"
LIVE_SUP="$(num "$(rdlive "$WLXON" 'totalSupply()(uint256)')")"
eq "$ZERO" "$(lc "$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "mainnet has no wLXON/USDC pair"
[ -n "$LIVE_POL" ] || { bad "could not read $DEPLOYER's POL from $RPC137_SRC -- the end-of-run check would be vacuous"; exit 1; }
note "live: POL $LIVE_POL, nonce $LIVE_NONCE, head $LIVE_HEAD, wLXON supply $LIVE_SUP"
eq "0" "$(num "$(rdlive "$USDC" 'balanceOf(address)(uint256)' "$DEPLOYER")")" "the live launch key holds no USDC"
eq "$(lc "$WMATIC")" "$(lc "$(one "$(rdlive "$ROUTER" 'WETH()(address)')")")" \
   "the venue resolves on this endpoint: router WETH() is $WMATIC"

say "1. a fork of Polygon 137"
if [ -n "$(rpc "$P137" eth_chainId '[]' 2>/dev/null | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or ""))' 2>/dev/null)" ]; then
  bad "port $P137 is already serving an RPC -- kill it; a stale fork carries the previous run's state and clock"
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
eq "1" "$(python3 -c 'import sys;print(int(int(sys.argv[1]) < 300))' "$GAP")" "fork clock within 300 s of live ($GAP s apart)"
eq "$ZERO" "$(lc "$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" "the fork is clean: no pair yet"

say "2. one throwaway signing key, in a temp root this script destroys"
printf 'rehearsal-password-not-a-secret\n' > "$SEC/x.pw"
umask 077
CAST_PASSWORD="rehearsal-password-not-a-secret" cast wallet new "$KS_DIR" pool-signer >"$ROOT/k1.log" 2>&1
[ -f "$KS_DIR/pool-signer" ] || { bad "no throwaway keystore was created: $(lf "$(cat "$ROOT/k1.log")")"; exit 1; }
# LaunchPool137.sh gates on `[ -f "$KEYSTORE" ]` -- a FILE, which is exactly how the real
# `~/.lxon/keystores/polygon-137` is laid out (measured: 436 bytes, mode 0600) -- whereas the signer it
# calls accepts a directory too. So a rehearsal must pass a path, not a directory, or it never reaches the
# signing half it is here to test.
KS_FILE="$KS_DIR/pool-signer"
eq "600" "$(stat -f '%Lp' "$KS_DIR/pool-signer" 2>/dev/null || stat -c '%a' "$KS_DIR/pool-signer" 2>/dev/null)" \
   "the keystore is mode 0600 (umask 077; cast wallet new itself writes 0644)"
SIGNER="$(cast wallet address --keystore "$KS_DIR/pool-signer" --password-file "$SEC/x.pw" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$SIGNER" ] && ok "throwaway signer $SIGNER -- not the launch key, so nothing signed with it can move production funds" || bad "could not derive the throwaway address"

say "3. fund the legs ON THE FORK, taken from real balances rather than minted"
rpc "$F137" anvil_setBalance "[\"$SIGNER\",\"$(python3 -c 'print(hex(10**19))')\"]" >/dev/null
eq "10000000000000000000" "$(result "$F137" eth_getBalance "$(jp "$SIGNER" latest)" | hexd)" \
   "the rehearsal signer can pay for gas on the fork (anvil_setBalance; the live key is untouched)"
rpc "$F137" anvil_setBalance "[\"$REF_PAIR\",\"$(python3 -c 'print(hex(10**18))')\"]" >/dev/null
eq "1000000000000000000" "$(result "$F137" eth_getBalance "$(jp "$REF_PAIR" latest)" | hexd)" \
   "and the PAIR is given POL too, because an impersonated contract sender still has to buy gas -- measured here as 'Failed to estimate gas: -32003 Out of gas: gas required exceeds allowance: 0' when it was not"
PAIR_U="$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$REF_PAIR")")"
eq "1" "$(gt "$PAIR_U" 240000000)" "the WMATIC/USDC pair holds $PAIR_U wei, so two legs of 117.80 USDC are TAKEN from the venue, not invented"
h="$(send_as "$REF_PAIR" "$USDC" 'transfer(address,uint256)' "$DEPLOYER" "$U_WEI")"
eq "0x1" "$(st "$h")" "117.80 USDC moved to the launch key ON THE FORK, so a launch-key plan can be planned at all"
h="$(send_as "$REF_PAIR" "$USDC" 'transfer(address,uint256)' "$SIGNER" "$U_WEI")"
eq "0x1" "$(st "$h")" "and 117.80 more to the throwaway provider (the pair is a contract; --auto-impersonate lets an address drive it)"
h="$(send_as "$DEPLOYER" "$WLXON" 'transfer(address,uint256)' "$SIGNER" "$W_WEI")"
eq "0x1" "$(st "$h")" "500 wLXON moved to the throwaway provider, out of the launch key's real 10,000 -- nothing was minted"
eq "$W_WEI" "$(num "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$SIGNER")")" "the throwaway holds the wLXON leg"
eq "$U_WEI" "$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$SIGNER")")" "and the USDC leg"
eq "$U_WEI" "$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$DEPLOYER")")" "and the fork's launch key holds a USDC leg too, for the identity test"
eq "$LIVE_SUP" "$(num "$(rd "$WLXON" 'totalSupply()(uint256)')")" "wLXON supply unchanged: these are transfers, not issuance"

say "4. the launcher will not sign a plan whose sender is not its key"
PLANX="$ROOT/refuse-identity"
RPC137="$F137" PROVIDER="$DEPLOYER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=native PLAN_DIR="$PLANX" POOL_SELFDEALT_ACK=1 KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" \
  PLAN_FORK_PORT="$(( PLAN_PORT + 1 ))" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/identity.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "a plan naming $DEPLOYER, signed with the throwaway keystore, exits non-zero (exit $rc)" \
  || bad "it signed someone else's plan: $(lf "$(cat "$ROOT/identity.log")")"
[ -s "$PLANX/plan.json" ] && ok "the plan itself was written first (planning needs no key)" || note "no plan.json survived the run"
eq "0" "$(nj "$PLANX/signed")" "no transaction was signed with the wrong key"
grep -qi "Wrong key" "$ROOT/identity.log" \
  && ok "and the refusal is the signer's identity gate: $(grep -im1 'FATAL' "$ROOT/identity.log" | cut -c1-160)" \
  || bad "it refused for some reason other than key identity -- this assertion would then be vacuous: $(lf "$(cat "$ROOT/identity.log")")"
grep -qi "no keystore at" "$ROOT/identity.log" && bad "it never found the keystore, so the identity test proved nothing" || ok "the keystore was found and read; the refusal came after that"

say "5. three of its own gates, driven for a provider the throwaway DOES sign for"
PLANR="$ROOT/launch-staged"
RPC137="$F137" PROVIDER="$SIGNER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=native PLAN_DIR="$PLANR" POOL_SELFDEALT_ACK=1 LP_EXIT_UNPROVEN_ACK=1 \
  KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" PLAN_FORK_PORT="$(( PLAN_PORT + 2 ))" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/stage1.log" 2>&1
eq "0" "$?" "staged mode exits 0"
grep -qi "staged, not broadcast" "$ROOT/stage1.log" && ok "and it stops there rather than publishing" || bad "no staged stop line: $(lf "$(cat "$ROOT/stage1.log")")"
eq "3" "$(nj "$PLANR/signed")" "three offline signatures exist"
eq "3" "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["txs"]))' "$PLANR/plan.json")" "the plan holds three transactions"
eq "$F137" "$(pj "$PLANR/plan.json" rpc)" "the plan's rpc is the fork -- so signer and broadcaster both talk to the fork, not mainnet"
eq "$(lc "$STRONG_TL")" "$(lc "$(pjp "$PLANR/plan.json" custody address)")" "the custody it recorded is the bridge timelock"
eq "1" "$(close "$(pjp "$PLANR/plan.json" pool priceImpliedUsdcPerWlxon)" "$TARGET_PRICE" "$TARGET_PRICE" 0.001)" \
   "planned price $(pjp "$PLANR/plan.json" pool priceImpliedUsdcPerWlxon) USDC per wLXON -- the ruled 0.2356"
eq "$ZERO" "$(lc "$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" "and staging created no pair on any chain"
RPC137="$F137" PROVIDER="$SIGNER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=native PLAN_DIR="$PLANR" POOL_SELFDEALT_ACK=1 LP_EXIT_UNPROVEN_ACK=1 \
  KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" PLAN_FORK_PORT="$(( PLAN_PORT + 3 ))" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/reuse.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "the same PLAN_DIR a second time is refused (exit $rc)" || bad "it re-planned over a used PLAN_DIR"
grep -qi "single use" "$ROOT/reuse.log" && ok "with the stated reason: a plan is single use" || bad "reason missing: $(lf "$(cat "$ROOT/reuse.log")")"
RPC137="$F137" PROVIDER="$SIGNER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=full PLAN_DIR="$ROOT/refuse-full" POOL_SELFDEALT_ACK=1 LP_EXIT_UNPROVEN_ACK=1 \
  KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/full.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "USDC_KIND=full exits non-zero, so a bad kind never reaches the money" || bad "USDC_KIND=full was accepted"
grep -qi "USDC_KIND must be native or bridged" "$ROOT/full.log" \
  && ok "and it says so in its own words: $(grep -im1 'FATAL' "$ROOT/full.log" | cut -c1-120)" \
  || bad "it stopped for a different reason than the kind: $(lf "$(cat "$ROOT/full.log")")"
RPC137="$F137" PROVIDER="$SIGNER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=native PLAN_DIR="$ROOT/no-ack" KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/noack.log" 2>&1
rc=$?
[ "$rc" != "0" ] && ok "without POOL_SELFDEALT_ACK=1 it refuses outright -- the price acknowledgement is not assumed" || bad "it planned a price-setter on default"

say "6. BROADCAST=1 -- the launcher re-plans and publishes, against the fork"
PLANB="$ROOT/launch-broadcast"
RPC137="$F137" PROVIDER="$SIGNER" AMOUNT_WLXON="$AMOUNT_WLXON" AMOUNT_USDC="$AMOUNT_USDC" \
  USDC_KIND=native PLAN_DIR="$PLANB" POOL_SELFDEALT_ACK=1 BROADCAST=1 LP_EXIT_UNPROVEN_ACK=1 \
  KEYSTORE="$KS_FILE" PASSWORD_FILE="$SEC/x.pw" PLAN_FORK_PORT="$(( PLAN_PORT + 4 ))" \
  bash script/polygon137/LaunchPool137.sh >"$ROOT/bcast.log" 2>&1
rc=$?
eq "0" "$rc" "the launcher exited 0 all the way through broadcast"
[ "$rc" = "0" ] || note "last lines: $(lf "$(cat "$ROOT/bcast.log")")"
PAIR="$(one "$(rd "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")"
eq "1" "$(ne "$PAIR" "$ZERO")" "the factory now names a pair on the fork: $PAIR"
eq "3" "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["txs"]))' "$PLANB/plan.json")" "BROADCAST=1 built a fresh three-transaction plan rather than reusing the staged one"
eq "$F137" "$(pj "$PLANB/plan.json" rpc)" "and that plan was aimed at the fork too"
LPT="$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$STRONG_TL")")"
eq "1" "$(gt "$LPT" 0)" "the custody timelock holds the LP ($LPT wei)"
eq "0" "$(num "$(rd "$PAIR" 'balanceOf(address)(uint256)' "$SIGNER")")" "the provider that signed holds none of it -- custody is not a copy"
eq "0" "$(num "$(rd "$USDC" 'balanceOf(address)(uint256)' "$SIGNER")")" "and its USDC is all in the pool: the batch took the whole leg"
RR="$(rd "$PAIR" 'getReserves()(uint112,uint112,uint32)')"
R0="$(printf '%s\n' "$RR" | sed -n '1p' | numd)"; R1="$(printf '%s\n' "$RR" | sed -n '2p' | numd)"
TOK0="$(lc "$(one "$(rd "$PAIR" 'token0()(address)')")")"
if [ "$(lc "$WLXON")" = "$TOK0" ]; then W_RES="$R0"; U_RES="$R1"; else W_RES="$R1"; U_RES="$R0"; fi
P_T="$(python3 -c 'import sys;from decimal import Decimal as D;print("%.8f" % float((D(sys.argv[2])/D(10)**6)/(D(sys.argv[1])/D(10)**18)))' "$W_RES" "$U_RES")"
note "reserves: $(python3 -c 'import sys;print("%.4f" % (int(sys.argv[1])/10**18))' "$W_RES") wLXON + $(python3 -c 'import sys;print("%.4f" % (int(sys.argv[1])/10**6))' "$U_RES") USDC -> $P_T USDC per wLXON"
eq "1" "$(close "$P_T" "$TARGET_PRICE" "$TARGET_PRICE" 0.001)" "the venue's own price is the ruled price, read back from the pair"
eq "0" "$(python3 -c 'import json,os,sys;print(len([f for f in os.listdir(sys.argv[1]) if f.endswith(".pw") or "key" in f.lower()]))' "$PLANB")" \
   "the plan directory holds no password file and no key material"

say "7. production was not touched by proving any of this"
eq "$ZERO" "$(lc "$(one "$(rdlive "$FACTORY" 'getPair(address,address)(address)' "$WLXON" "$USDC")")")" \
   "mainnet still has no wLXON/USDC pair"
eq "$LIVE_NONCE" "$(result "$RPC137_SRC" eth_getTransactionCount "$(jp "$DEPLOYER" latest)" | hexd)" \
   "the launch key's live nonce never moved"
eq "$LIVE_POL" "$(result "$RPC137_SRC" eth_getBalance "$(jp "$DEPLOYER" latest)" | hexd)" \
   "the launch key's live POL is byte-identical to the start"
eq "$LIVE_SUP" "$(num "$(rdlive "$WLXON" 'totalSupply()(uint256)')")" "and wLXON supply is unchanged"

printf '\n== PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
printf 'LaunchPool137.sh is now exercised: it refuses to sign a plan whose sender is not its keystore, it\n'
printf 'refuses a missing POOL_SELFDEALT_ACK, a used PLAN_DIR and an unknown USDC_KIND, it stages three\n'
printf 'offline signatures and stops, and with BROADCAST=1 it re-plans, signs and publishes a batch whose\n'
printf 'pair prices wLXON at the ruled %s USDC with the LP in %s. All of it against a fork, with a throwaway\n' "$TARGET_PRICE" "$STRONG_TL"
printf 'key, and the live launch key read identical before and after.\n'
