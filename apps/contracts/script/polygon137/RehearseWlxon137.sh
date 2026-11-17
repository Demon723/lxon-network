#!/usr/bin/env bash
# Prove the whole Polygon-137 plan -> sign -> broadcast route works, before any of it is done for real.
#
#   FORK_RPC=http://127.0.0.1:8546 bash script/polygon137/RehearseWlxon137.sh
#   (or let it start the fork itself: UPSTREAM=<a 137 archive rpc> bash script/polygon137/RehearseWlxon137.sh)
#
# Why this exists rather than a unit test: the thing being rehearsed is not the contracts, it is the
# *hand-off between three machines that each see only part of the ceremony*. A plan made without a key,
# signed without a network write, and broadcast without a key has four ways to fail that no test of the
# Solidity can find -- a mis-encoded constructor argument that still mines, a predicted address that was
# already occupied, a fee field spelled for a legacy chain, a signed file that decodes against a plan
# from a different run. So the assertions here are against a node answering for chain 137: the chain is
# the authority, not this script's own variables.
#
# The key is a throwaway generated in a temp directory and destroyed at the end. Nothing on this machine
# signs a real launch with it, and nothing here can: the deployer address never leaves this fork.
#
# Exits non-zero on the first failed assertion group and prints the count. A rehearsal that prints
# "done" without a number is a script that ran.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="script/polygon137/lib/offline_plan1559.py"
PLAN_LIB="script/polygon137/lib/plan137.py"
CANON=/Users/adikamble/LXON/attested-bridge-wt/apps/contracts/script/v41/lib/offline_plan1559.py

FORK_RPC="${FORK_RPC:-http://127.0.0.1:8546}"
CHAIN_ID_EXPECT=137
LEGACY_WLXON=0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6
NATIVE_LXON=0x99801a78639975d448eeb2f8a807738dc8df67dc

PASSED=0; FAILED=0; SKIP=0; LOG=/tmp/wlxon137-rehearse-$$.log
ok()   { PASSED=$((PASSED+1)); printf '  ok   %3d  %s\n' "$PASSED" "$1"; }
bad()  { FAILED=$((FAILED+1)); printf '  FAIL %3d  %s\n' "$FAILED" "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; return 0; }
skip() { SKIP=$((SKIP+1)); printf '  --   skip: %s\n' "$1"; }
note() { printf '\n== %s ==\n' "$1"; }

# `expect <desc> <needle> <cmd...>`: run it, log it, and assert the needle is in the output or status.
expect() {
  local desc="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  printf '%s\n---- rc=%s\n%s\n\n' "$desc" "$rc" "$out" >> "$LOG"
  case "$out" in *"$needle"*) ok "$desc" ;; *) bad "$desc" "wanted 「$needle」, rc=$rc, output: $(printf '%s' "$out" | head -3 | tr '\n' ' ' | head -c 160)" ;; esac
}
expect_rc() { # expect_rc <desc> <wanted-rc> <cmd...>
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  printf '%s\n---- rc=%s\n%s\n\n' "$desc" "$rc" "$out" >> "$LOG"
  [ "$rc" = "$want" ] && ok "$desc" || bad "$desc" "wanted rc=$want, got rc=$rc"
}
eq() { # eq <desc> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi
}
rpc() { cast rpc "$@" --rpc-url "$FORK_RPC" 2>/dev/null | tr -d '"'; }
rawjson() { cast rpc "$@" --rpc-url "$FORK_RPC" 2>/dev/null; }
addr_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# ---------------------------------------------------------------- the node -----------------------
note "the node"
if ! cast rpc eth_chainId --rpc-url "$FORK_RPC" >/dev/null 2>&1; then
  [ -n "${UPSTREAM:-}" ] || { echo "FATAL: no node at $FORK_RPC and UPSTREAM=<a chain-137 rpc> is not set; start the fork with:"; echo "  anvil --fork-url <upstream> --fork-block-number <decimal block> --fork-chain-id 137 --port 8546"; exit 1; }
  # --fork-block-number is REQUIRED by foundry 1.8.4 whenever --fork-chain-id is passed (measured: without it
  # anvil dies with "the following required arguments were not provided: --fork-block-number"), and it takes
  # a DECIMAL integer -- handing it the hex eth_blockNumber returns dies with "invalid digit found in string".
  # An anvil that exits immediately used to leave this script waiting on a port and then reporting a chain-id
  # failure, which reads like a fork problem and is really a flag-order problem.
  UP_HEX="$(cast rpc eth_blockNumber --rpc-url "$UPSTREAM" 2>/dev/null | tr -d '"')"
  [ -n "$UP_HEX" ] || { echo "FATAL: $UPSTREAM did not answer eth_blockNumber, so there is no block to fork from" >&2; exit 1; }
  UP_BLOCK="$(python3 -c "print(int('$UP_HEX',16))")"
  anvil --fork-url "$UPSTREAM" --fork-block-number "$UP_BLOCK" --fork-chain-id 137 --port "${FORK_PORT:-8546}" >/tmp/wlxon137-anvil.log 2>&1 &
  ANVIL_PID=$!
  trap 'kill ${ANVIL_PID:-} 2>/dev/null' EXIT
  for _ in $(seq 1 60); do cast rpc eth_chainId --rpc-url "$FORK_RPC" >/dev/null 2>&1 && break; sleep 1; done
  cast rpc eth_chainId --rpc-url "$FORK_RPC" >/dev/null 2>&1 || { echo "FATAL: anvil did not come up on $FORK_RPC; its log said:"; tail -5 /tmp/wlxon137-anvil.log >&2; exit 1; }
fi
got_chain="$(rpc eth_chainId)"
eq "the fork answers chain 137 (so a 137 plan is priced and decoded against a real 137)" "0x89" "$got_chain"
BASE="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$FORK_RPC" 2>/dev/null | python3 -c 'import sys,json;b=json.load(sys.stdin);b=b.get("result",b);print(int(b.get("baseFeePerGas","0x0"),16))' 2>/dev/null || echo '')"
[ -n "$BASE" ] && [ "$BASE" -gt 0 ] && ok "the fork has a non-zero base fee ($BASE wei) -- a 0 maxFee would be rejected, so this rehearsal cannot pass on legacy-style fees" || bad "the fork has no base fee to check against" "base=$BASE"

# ---------------------------------------------------------------- the throwaway keys ---------------
note "throwaway keys (generated here, destroyed at the end -- never a real ceremony's)"
WORK="$(mktemp -d)"
cleanup() { [ -n "${ANVIL_PID:-}" ] && kill "$ANVIL_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
KS="$WORK/ks"; mkdir -p "$KS"
DEPLOY_PW="rehearsal-deployer-$RANDOM"
TIME_PW="rehearsal-timelock-$RANDOM"
printf '%s\n' "$DEPLOY_PW" > "$WORK/pw-deploy"; printf '%s\n' "$TIME_PW" > "$WORK/pw-timelock"
CAST_PASSWORD="$DEPLOY_PW" cast wallet new "$KS" 137deployer >/dev/null 2>&1
CAST_PASSWORD="$TIME_PW"  cast wallet new "$KS" 137timelock >/dev/null 2>&1
[ -f "$KS/137deployer" ] || { echo "FATAL: no keystore named 137deployer in $KS -- see $LOG"; exit 1; }
DEPLOYER="$(cast wallet address --keystore "$KS/137deployer" --password-file "$WORK/pw-deploy" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
EOA_ADMIN="$(cast wallet address --keystore "$KS/137timelock" --password-file "$WORK/pw-timelock" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$DEPLOYER" ] && [ -n "$EOA_ADMIN" ] && ok "two throwaway keystores minted ($DEPLOYER signs, $EOA_ADMIN is the codeless admin used only to prove it is refused)" || { echo "FATAL: cannot read addresses back out of the keystores"; exit 1; }
[ "$(addr_lc "$DEPLOYER")" != "$(addr_lc "$EOA_ADMIN")" ] && ok "the admin is not the signer -- so an un-timelocked configuration cannot be mistaken for the rehearsed one"
rpc anvil_setBalance "$DEPLOYER" 0x3635c9adc5dea00000 >/dev/null
bal="$(rpc eth_getBalance "$(addr_lc "$DEPLOYER")")"
[ "$bal" != "0x0" ] && ok "the throwaway holds gas on the fork ($(python3 -c "print(int('$bal',16)//10**18)") POL)" || bad "anvil_setBalance did not fund the throwaway"

# The admin has to be a contract, because that is the ruling the real ceremony follows. Rather than
# pretend an EOA is a Timelock, install the app's own compiled TimelockController bytecode at a
# rehearsal address and check the chain agrees the bytes are there -- so every readback below asserts
# the custody shape that ships, not a convenient stand-in.
TIMELOCK=0x7777777777777777777777777777777777777777
TL_ART=artifacts/@openzeppelin/contracts/governance/TimelockController.sol/TimelockController.json
# No 0x prepended: the artifact's bytecode field already carries it, and `0x0x6080…` is what anvil
# rejects -- an error that reads like a node problem and is really a string-joining one.
TL_BYTECODE="$(python3 -c "import json;print(json.load(open('$TL_ART'))['bytecode'])")"
rpc anvil_setCode "$TIMELOCK" "$TL_BYTECODE" >/dev/null
installed="$(rpc eth_getCode "$(addr_lc "$TIMELOCK")")"
[ "${installed:0:60}" = "${TL_BYTECODE:0:60}" ] && ok "the rehearsal admin is a contract: eth_getCode at $TIMELOCK returns the compiled TimelockController bytes" || bad "anvil_setCode did not install the TimelockController bytecode at the rehearsal admin"

# ---------------------------------------------------------------- hygiene of the halves ----------
note "what each half refuses, before anything is signed"
PLAN_BASE="$WORK/plans"; mkdir -p "$PLAN_BASE"
mkplan() { # mkplan <phase> <name> -- fresh dir under $PLAN_BASE, echoes the path
  local d="$PLAN_BASE/$2"; mkdir -p "$d"; printf '%s' "$d";
}
P1="$(mkplan deploy p1)"
BASE_ENV=(PHASE=deploy PLAN_DIR="$P1" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC"
  WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK=create WLXON_MIGRATION_OLD="$LEGACY_WLXON"
  WLXON_EXPECT_CHAIN_ID=137 WLXON_I_ACCEPT_MAINNET_RISK=1)
expect_rc "the planner refuses to run into an existing non-empty PLAN_DIR" 1 \
  env PHASE=deploy PLAN_DIR="$WORK" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$TIMELOCK" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
# the refusals must come from the real script, not from a stub:
expect "the planner refuses a key on the command line" "PLAN mode needs no key" \
  env PRIVATE_KEY=0x$(printf '11%.0s' {1..64}) PHASE=deploy PLAN_DIR="$WORK/pk" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$TIMELOCK" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses a keystore it does not need" "PLAN mode needs no keystore" \
  env KEYSTORE="$KS/137deployer" PHASE=deploy PLAN_DIR="$WORK/ks1" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$TIMELOCK" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses chain 137 without saying it means mainnet" "Polygon MAINNET" \
  env PHASE=deploy PLAN_DIR="$WORK/nm" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$TIMELOCK" WLXON_MIGRATION_OLD="$LEGACY_WLXON" bash script/polygon137/PlanWlxon137.sh
expect "the planner stops when the node's chain id is not the one the run was guarded for" "guarded for" \
  env "${BASE_ENV[@]}" WLXON_EXPECT_CHAIN_ID=80002 PHASE=deploy PLAN_DIR="$WORK/wc" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$TIMELOCK" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses a placeholder address instead of encoding it" "looks like a placeholder" \
  env PHASE=deploy PLAN_DIR="$WORK/ph" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON=0x1111111111111111111111111111111111111111 WLXON_TIMELOCK="$TIMELOCK" \
      WLXON_MIGRATION_OLD="$LEGACY_WLXON" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses quorum 1 -- one signer is not a quorum" "one stolen key" \
  env "${BASE_ENV[@]}" WLXON_QUORUM=1 PHASE=deploy PLAN_DIR="$WORK/q1" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses an ADMIN_ROLE that is not a contract on the target chain" "WLXON_I_ACCEPT_ADMIN_HAS_NO_CODE" \
  env PHASE=deploy PLAN_DIR="$WORK/tl" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$EOA_ADMIN" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses an admin that is the signer, unless told" "WLXON_I_ACCEPT_ADMIN_IS_DEPLOYER" \
  env PHASE=deploy PLAN_DIR="$WORK/adm" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      WLXON_NATIVE_LXON="$NATIVE_LXON" WLXON_TIMELOCK="$DEPLOYER" WLXON_MIGRATION_OLD="$LEGACY_WLXON" \
      WLXON_I_ACCEPT_ADMIN_HAS_NO_CODE=1 WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
expect "the planner refuses a gas cap below the number the rehearsal measured" "lowering one below" \
  env CAP_SETOLDTOKEN=1 bash -c "python3 $PLAN_LIB cap setOldToken"
expect "the planner refuses a self-created timelock with less than a 48h delay" "under 48h" \
  env "${BASE_ENV[@]}" TIMELOCK_MIN_DELAY=3600 PHASE=deploy PLAN_DIR="$WORK/md" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      bash script/polygon137/PlanWlxon137.sh
expect "and it refuses a non-address in the proposer list rather than encoding garbage" "not a 20-byte address" \
  env "${BASE_ENV[@]}" TIMELOCK_PROPOSERS="0x1234,not-an-address" PHASE=deploy PLAN_DIR="$WORK/pr" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" \
      bash script/polygon137/PlanWlxon137.sh
# The other branch stays available: a governance contract that already exists on 137 is used as-is, and
# the batch is four transactions because it does not have to build the custody.
out="$(env "${BASE_ENV[@]}" WLXON_TIMELOCK="$TIMELOCK" PHASE=deploy PLAN_DIR="$WORK/ex" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" bash script/polygon137/PlanWlxon137.sh 2>&1)"; rc=$?
printf 'plan-existing rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "the existing-address branch still plans (four transactions, no TIMELOCK step)" || bad "the existing-address branch exited $rc" "$(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
PLAN_DIR="$WORK/ex"
eq "and it is four transactions" "4" "$(PLAN_DIR="$WORK/ex" python3 "$LIB" txs | wc -l | tr -d ' ')"
[ -z "$(PLAN_DIR="$WORK/ex" python3 "$LIB" field predictedTimelock)" ] && ok "with no timelock created, plan.json says so instead of inventing one"
export PLAN_DIR="$P1"

# ---------------------------------------------------------------- plan: deploy -------------------
note "the deploy plan (no key anywhere in this half)"
out="$(env "${BASE_ENV[@]}" PHASE=deploy PLAN_DIR="$P1" bash script/polygon137/PlanWlxon137.sh 2>&1)"; rc=$?
printf 'plan-deploy rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "PHASE=deploy planned five transactions (timelock first)" || bad "PHASE=deploy exited $rc" "$(printf '%s' "$out" | tail -6 | tr '\n' ' ')"
[ -f "$P1/plan.json" ] && ok "plan.json written" || { echo "FATAL: no plan.json; nothing after this can be checked. Log: $LOG"; exit 1; }
export PLAN_DIR="$P1"
CHAINP="$(python3 "$LIB" field chainId)"; FROMP="$(python3 "$LIB" field from)"
NTX="$(python3 "$LIB" field txCount)"; START="$(python3 "$LIB" field startNonce)"
MAXFP="$(python3 "$LIB" field maxFeePerGasWei)"; PRIP="$(python3 "$LIB" field maxPriorityFeePerGasWei)"
PWX="$(python3 "$LIB" field predictedWlxon)"; PM="$(python3 "$LIB" field predictedMigration)"
eq "the plan names chain 137" "137" "$CHAINP"
eq "the plan names the throwaway as its signer" "$(addr_lc "$DEPLOYER")" "$(addr_lc "$FROMP")"
eq "the plan is five transactions" "5" "$NTX"
eq "the plan is phase deploy" "deploy" "$(python3 "$LIB" field phase)"
[ "$([ "$MAXFP" -ge "$(( ${BASE:-0} + PRIP ))" ] && echo yes)" = "yes" ] && ok "maxFee $MAXFP covers base $BASE + tip $PRIP" || bad "maxFee is below base+tip"
labels="$(python3 "$LIB" txs | cut -f1 | tr '\n' ',')"
eq "the steps are in the order the custody needs (timelock before the token that names it)" "TIMELOCK,WLXON,MIGRATION,setOldToken,setNewToken," "$labels"
PTL="$(python3 "$LIB" field predictedTimelock)"
nonces="$(python3 "$LIB" txs | cut -f2 | tr '\n' ' ')"
want_nonces="$(python3 -c "print(' '.join(str(n) for n in range($START, $START+5)) + ' ')")"
eq "the nonces are one contiguous run" "$want_nonces" "$nonces"
[ "$(addr_lc "$PWX")" != "$(addr_lc "$PM")" ] && ok "the two predicted addresses differ (one key, two contracts, two nonces)"
[ -n "$PWX" ] && printf '%s' "$PWX" | grep -Eq '^0x[0-9a-fA-F]{40}$' && ok "predicted wLXONSecure $PWX is a 20-byte address"
[ -n "$PTL" ] && printf '%s' "$PTL" | grep -Eq '^0x[0-9a-fA-F]{40}$' && ok "predicted timelock $PTL is a 20-byte address"
[ "$(addr_lc "$PTL")" != "$(addr_lc "$PWX")" ] && ok "the timelock and the token are different addresses -- one key, three contracts, three nonces"
code_at_pred="$(rpc eth_getCode "$(addr_lc "$PWX")")"
eq "the predicted address is still empty on chain (so the prediction can still come true)" "0x" "$code_at_pred"
eq "the predicted timelock address is empty too" "0x" "$(rpc eth_getCode "$(addr_lc "$PTL")")"
# Lines are read BY LABEL, not by position: the batch grew a step at the front when the timelock moved
# inside it, and a rehearsal that greps `sed -n 3p` would have quietly asserted about the wrong step.
tx_line() { python3 "$LIB" txs | awk -F'\t' -v l="$1" '$1==l {print; exit}'; }
tl_data="$(tx_line TIMELOCK | cut -f5)"
tl_byte="$(python3 "$PLAN_LIB" bytecode TimelockController 2>/dev/null)"
[ "${tl_data:0:${#tl_byte}}" = "$tl_byte" ] && ok "the TIMELOCK step's payload begins with the compiled TimelockController bytecode" || bad "the planned timelock creation is not this artifact's bytecode"
abi_tail() { printf '%s' "$2" | python3 -c "import sys;print(sys.argv[1][len(sys.argv[2]):])" "$1" "$2" 2>/dev/null; }
hexword_dec() { printf '%s' "${1:-0}" | python3 -c 'import sys; print(int(sys.stdin.read().strip() or "0", 16))'; }
word() { printf '%s' "$1" | cut -c$(( $2 * 64 + 1 ))-$(( $2 * 64 + 64 )); }   # ZERO-based: word 0 is the first 32 bytes
addr_word() { printf '0x%s' "$(word "$1" "$2" | cut -c25-64)"; }
tl_args="$(abi_tail "$tl_data" "$tl_byte")"
tl_delay="$(hexword_dec "$(word "$tl_args" 0)")"
tl_prop0="$(addr_word "$tl_args" 5)"
tl_admin="$(addr_word "$tl_args" 3)"
eq "the timelock is created with a 48h minDelay, not 0" "172800" "$tl_delay"
eq "and the deployer is one of its proposers" "$(addr_lc "$DEPLOYER")" "$(addr_lc "$tl_prop0")"
eq "and the deployer is its admin (DEFAULT_ADMIN_ROLE)" "$(addr_lc "$DEPLOYER")" "$(addr_lc "$tl_admin")"
wlxon_step="$(tx_line WLXON)"
ctor_data="$(printf '%s' "$wlxon_step" | cut -f5)"
bytecode="$(python3 "$PLAN_LIB" bytecode wLXONSecure 2>/dev/null)"
[ "${ctor_data:0:${#bytecode}}" = "$bytecode" ] && ok "the WLXON step's payload begins with the compiled bytecode of wLXONSecure -- the plan deploys THIS build" || bad "the planned creation is not this artifact's bytecode"
w_args="$(abi_tail "$ctor_data" "$bytecode")"
w_admin="$(addr_word "$w_args" 5)"
w_target="$(hexword_dec "$(word "$w_args" 4)")"   # 0 = nameOff, 1 = symOff, 2 = native, 3 = source, 4 = target
w_source="$(hexword_dec "$(word "$w_args" 3)")"
eq "wLXONSecure's argument 6 (ADMIN_ROLE) is the address the timelock is predicted to have" "$(addr_lc "$PTL")" "$(addr_lc "$w_admin")"
eq "and argument 5 (targetChainId) is 137" "137" "$w_target"
eq "and argument 4 (sourceChainId) is 724" "724" "$w_source"
old_step="$(tx_line setOldToken)"
eq "setOldToken is aimed at the predicted migration contract" "$(addr_lc "$PM")" "$(addr_lc "$(printf '%s' "$old_step" | cut -f3)")"
new_step="$(tx_line setNewToken)"
eq "setNewToken is aimed at the predicted migration contract" "$(addr_lc "$PM")" "$(addr_lc "$(printf '%s' "$new_step" | cut -f3)")"
decoded_old="$(cast calldata-decode "setOldToken(address)" "$(printf '%s' "$old_step" | cut -f5)" | head -1)"
eq "setOldToken's argument decodes as the legacy wLXON (the chain's own ABI decoder, not this script's)" "$(addr_lc "$LEGACY_WLXON")" "$(addr_lc "$decoded_old")"
decoded_new="$(cast calldata-decode "setNewToken(address)" "$(printf '%s' "$new_step" | cut -f5)" | head -1)"
eq "setNewToken's argument decodes as the predicted wLXONSecure" "$(addr_lc "$PWX")" "$(addr_lc "$decoded_new")"
[ -n "${PM:-}" ] && [ "$(rpc eth_getCode "$(addr_lc "$PM")")" = "0x" ] && ok "the predicted migration address is also empty"
grep -q "CREATES a TimelockController" "$P1/MANIFEST.txt" && ok "the manifest states in its own words that custody is created by this batch, not inherited"
grep -q "DOES NOT OPEN THE WINDOW" "$P1/MANIFEST.txt" && ok "the manifest says plainly that this batch leaves the window closed"
grep -q "single-use" "$P1/MANIFEST.txt" && ok "the manifest tells the operator the signed batch is single-use"
# the vendored checker must still be the canonical one -- a copy edited for this ceremony cannot catch what it was edited to allow
if [ -f "$CANON" ]; then
  a="$(shasum -a 256 "script/polygon137/lib/offline_plan1559.py" | cut -d' ' -f1)"
  b="$(shasum -a 256 "$CANON" | cut -d' ' -f1)"
  eq "the vendored verifier is byte-identical to the one that checks the live bridge ceremony" "$b" "$a"
else
  skip "canonical lib not reachable at $CANON -- the vendored copy went unchecked this run"
fi

# ---------------------------------------------------------------- sign: the key host -----------
note "the signer (this is the half that holds a key, and the half that must not write to a chain)"
S1="$P1/signed"
expect "the signer refuses a PRIVATE_KEY on the command line" "KEYSTORE=/PASSWORD_FILE= only" \
  env PLAN_DIR="$P1" SIGNED_DIR="$WORK/s-pk" KEYSTORE="$KS/137deployer" PASSWORD_FILE="$WORK/pw-deploy" \
      PRIVATE_KEY=0x$(printf '22%.0s' {1..64}) bash script/polygon137/SignWlxon137Plan.sh
expect "the signer refuses a plan made for another address" "Wrong key" \
  env PLAN_DIR="$P1" SIGNED_DIR="$WORK/s-wrong" KEYSTORE="$KS/137timelock" PASSWORD_FILE="$WORK/pw-timelock" bash script/polygon137/SignWlxon137Plan.sh
expect "the signer refuses a password given inline rather than as a file" "PASSWORD_FILE" \
  env PLAN_DIR="$P1" SIGNED_DIR="$WORK/s-nopw" KEYSTORE="$KS/137deployer" bash script/polygon137/SignWlxon137Plan.sh
out="$(env PLAN_DIR="$P1" KEYSTORE="$KS/137deployer" PASSWORD_FILE="$WORK/pw-deploy" bash script/polygon137/SignWlxon137Plan.sh 2>&1)"; rc=$?
printf 'sign rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "the key host signed all five lines" || bad "the signer exited $rc" "$(printf '%s' "$out" | tail -5 | tr '\n' ' ')"
eq "five signed files came back" "5" "$(ls -1 "$S1"/*.raw.hex 2>/dev/null | wc -l | tr -d ' ')"
sig_labels="$(ls -1 "$S1" | sed 's/\.raw\.hex$//' | tr '\n' ',')"
eq "the signed files are indexed and named for the plan's steps in order" "00-TIMELOCK,01-WLXON,02-MIGRATION,03-setOldToken,04-setNewToken," "$sig_labels"
k=0; allv=1
while IFS="$(printf '\t')" read -r label nonce to value data gas maxfee priority; do
  f="$S1/$(printf '%02d' "$k")-$label.raw.hex"
  python3 "$LIB" verify "$f" "$nonce" "$to" "$value" "$data" "$gas" "$maxfee" "$priority" "$CHAINP" "$DEPLOYER" >/dev/null || allv=0
  k=$((k+1))
done < <(python3 "$LIB" txs)
[ "$allv" = 1 ] && ok "every signature decodes back to exactly its plan line (nonce, fees, gas, data, chain, signer)" || bad "a signature does not decode as the plan says"

# a moved nonce is the failure a launch actually hits: the plan is hours old and something else spent a nonce
rpc anvil_setNonce "$DEPLOYER" $((START + 1)) >/dev/null
expect "the signer refuses once the deployer's nonce has moved -- and tells the operator to re-plan, not to shift nonces by hand" "re-plan" \
  env PLAN_DIR="$P1" SIGNED_DIR="$WORK/s-drift" KEYSTORE="$KS/137deployer" PASSWORD_FILE="$WORK/pw-deploy" bash script/polygon137/SignWlxon137Plan.sh
rpc anvil_setNonce "$DEPLOYER" $START >/dev/null

# ---------------------------------------------------------------- broadcast: tamper -------------
note "the broadcaster (sees signatures and a node, never a key)"
cp "$S1/03-setOldToken.raw.hex" "$WORK/setold.orig"
python3 - "$S1/03-setOldToken.raw.hex" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().strip()
i = len(s) - 40                      # inside the last word of calldata, not the signature
flip = '0' if s[i] != '0' else '1'
open(p, "w").write(s[:i] + flip + s[i+1:] + "\n")
PY
nonce_before="$(rpc eth_getTransactionCount "$(addr_lc "$DEPLOYER")")"
expect_rc "a tampered signature is refused before anything is published" 1 \
  env PLAN_DIR="$P1" SIGNED_DIR="$S1" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh
expect "the tampered line is named, not just rejected" "03-setOldToken" \
  env PLAN_DIR="$P1" SIGNED_DIR="$S1" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh
nonce_after="$(rpc eth_getTransactionCount "$(addr_lc "$DEPLOYER")")"
eq "nothing was published by the refused batch (the nonce did not move)" "$nonce_before" "$nonce_after"
cp "$WORK/setold.orig" "$S1/03-setOldToken.raw.hex"
expect "the signer will not sign twice into a directory that already holds signatures" "not empty" \
  env PLAN_DIR="$P1" KEYSTORE="$KS/137deployer" PASSWORD_FILE="$WORK/pw-deploy" bash script/polygon137/SignWlxon137Plan.sh

# ---------------------------------------------------------------- broadcast: deploy -----------
out="$(env PLAN_DIR="$P1" SIGNED_DIR="$S1" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"; rc=$?
printf 'broadcast-deploy rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "the signed deploy batch broadcast clean" || bad "the broadcaster exited $rc" "$(printf '%s' "$out" | tail -8 | tr '\n' ' ')"
printf '%s' "$out" | grep -q "created at $(addr_lc "$PWX")" && ok "wLXONSecure mined at exactly the address the plan predicted before any key was involved" || bad "the chain put wLXONSecure somewhere else"
printf '%s' "$out" | grep -q "created at $(addr_lc "$PM")" && ok "the migration contract mined at its predicted address"
nonce_now="$(rpc eth_getTransactionCount "$(addr_lc "$DEPLOYER")")"
eq "the deployer is 5 nonces further on" "0x$(printf '%x' $((START + 5)))" "$nonce_now"
ADMIN_ID="$(cast keccak 'ADMIN_ROLE')"
eq "chain: nativeLXON is the LXON the plan named" "$(addr_lc "$NATIVE_LXON")" "$(addr_lc "$(cast call "$PWX" 'nativeLXON()(address)' --rpc-url "$FORK_RPC" | head -1)")"
eq "chain: sourceChainId is 724" "724" "$(cast call "$PWX" 'sourceChainId()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
eq "chain: targetChainId is 137" "137" "$(cast call "$PWX" 'targetChainId()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
eq "chain: quorum is 2 -- not 0, not 1" "2" "$(cast call "$PWX" 'quorum()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
eq "chain: ADMIN_ROLE belongs to the timelock THIS BATCH created, not the signer" "true" "$(cast call "$PWX" 'hasRole(bytes32,address)(bool)' "$ADMIN_ID" "$PTL" --rpc-url "$FORK_RPC" | head -1)"
eq "chain: the deployer holds no ADMIN_ROLE (so this batch did not hand itself the bridge)" "false" "$(cast call "$PWX" 'hasRole(bytes32,address)(bool)' "$ADMIN_ID" "$DEPLOYER" --rpc-url "$FORK_RPC" | head -1)"
eq "chain: the timelock landed at the predicted address and has code" "yes" "$([ "$(rpc eth_getCode "$(addr_lc "$PTL")")" != "0x" ] && echo yes)"
eq "chain: the timelock's delay is 48h" "172800" "$(cast call "$PTL" 'getMinDelay()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
eq "chain: the deployer can propose (so governance is reachable, just not instant)" "true" "$(cast call "$PTL" "hasRole(bytes32,address)(bool)" "$(cast keccak 'PROPOSER_ROLE')" "$DEPLOYER" --rpc-url "$FORK_RPC" | head -1)"
# The decisive custody test, and the only one that could not be written by reading the plan: ask the node
# to run addAttestor as the deployer. If it estimates, the delay is decorative and the key still rules the
# bridge. It has to fail.
att_est="$(cast rpc eth_estimateGas "{\"from\":\"$(addr_lc "$DEPLOYER")\",\"to\":\"$(addr_lc "$PWX")\",\"data\":\"$(cast calldata 'addAttestor(address)' "$(addr_lc "$DEPLOYER")")\"}" --rpc-url "$FORK_RPC" 2>&1 | head -1)"
case "$att_est" in *revert*|*AccessControl*|*MissingRole*|*error*) ok "chain: the deployer's own addAttestor call is refused -- the timelock is the only way to configure the bridge" ;; *) bad "the deployer could call addAttestor directly; ADMIN_ROLE is not actually behind a delay" "$att_est" ;; esac
eq "chain: the migration contract's oldWLXON is the legacy token" "$(addr_lc "$LEGACY_WLXON")" "$(addr_lc "$(cast call "$PM" 'oldWLXON()(address)' --rpc-url "$FORK_RPC" | head -1)")"
eq "chain: the migration contract's newWLXON is the wLXONSecure this batch deployed" "$(addr_lc "$PWX")" "$(addr_lc "$(cast call "$PM" 'newWLXON()(address)' --rpc-url "$FORK_RPC" | head -1)")"
eq "chain: the migration window is still closed" "false" "$(cast call "$PM" 'migrationActive()(bool)' --rpc-url "$FORK_RPC" | head -1)"
eq "chain: there is no reserve yet" "0" "$(cast call "$PM" 'reserveBalance()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
[ -f "$P1/launch-record.json" ] && ok "a launch record was written" || bad "no launch-record.json -- a launch you cannot re-read is a rumour"
h0="$(python3 -c "import json;print(json.load(open('$P1/launch-record.json'))['steps'][0]['txHash'])")"
byhash="$(rawjson eth_getTransactionByHash "$h0")"
printf '%s' "$byhash" | grep -q '"hash"' && ok "the record's first tx hash resolves as a transaction (not a block hash wearing a tx hash)" || bad "eth_getTransactionByHash returned nothing for the recorded hash $h0"
rec_nonce="$(printf '%s' "$byhash" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["nonce"],16))' 2>/dev/null || echo '?')"
eq "and it is the creation the plan put at its first nonce" "$START" "$rec_nonce"

# ---------------------------------------------------------------- plan: fund ------------------
note "the fund plan (the reserve cannot exist before the token does)"
RESERVE=20000000000000000000000
P2="$(mkplan fund p6)"
FUND_ENV=(PHASE=fund PLAN_DIR="$P2" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC"
  WLXON_MIGRATION_NEW="$PWX" WLXON_MIGRATION="$PM" WLXON_RESERVE="$RESERVE"
  WLXON_MIGRATION_DAYS=30 WLXON_START_MIGRATION=1 WLXON_EXPECT_CHAIN_ID=137
  WLXON_I_ACCEPT_MAINNET_RISK=1)
expect "the fund plan refuses while the deployer holds none of the new token" "the reserve is not spendable yet" \
  env "${FUND_ENV[@]}" PLAN_DIR="$WORK/pf1" bash script/polygon137/PlanWlxon137.sh
expect "the fund plan refuses a zero reserve" "no reserve" \
  env PHASE=fund PLAN_DIR="$WORK/p3" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" WLXON_MIGRATION_NEW="$PWX" \
      WLXON_MIGRATION="$PM" WLXON_RESERVE=0 WLXON_START_MIGRATION=1 WLXON_I_ACCEPT_MAINNET_RISK=1 \
      bash script/polygon137/PlanWlxon137.sh
expect "the fund plan refuses to move tokens without opening the window" "PHASE=fund exists to open the window" \
  env PHASE=fund PLAN_DIR="$WORK/p4" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" WLXON_MIGRATION_NEW="$PWX" \
      WLXON_MIGRATION="$PM" WLXON_RESERVE="$RESERVE" WLXON_I_ACCEPT_MAINNET_RISK=1 \
      bash script/polygon137/PlanWlxon137.sh
expect "the fund plan refuses a window shorter than the contract allows" "at least 7 days" \
  env PHASE=fund PLAN_DIR="$WORK/p5" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" WLXON_MIGRATION_NEW="$PWX" \
      WLXON_MIGRATION="$PM" WLXON_RESERVE="$RESERVE" WLXON_MIGRATION_DAYS=3 WLXON_START_MIGRATION=1 \
      WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh

# Give the throwaway a balance the way a bridged deposit would leave one: an ERC20 balance is a storage
# slot, and the slot is derived from the compiler's own storage layout (verified below by reading the
# value back through balanceOf -- so a wrong slot cannot pass this rehearsal).
BAL_SLOT="$(forge inspect wLXONSecure storage-layout --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for e in d["storage"]:
    if e["label"] == "_balances":
        print(e["slot"]); break
else:
    raise SystemExit(1)')"
eq "the ERC20 balances mapping is slot 0 of wLXONSecure (asked the compiler, not memory)" "0" "$BAL_SLOT"
SLOT="$(cast index address "$(addr_lc "$DEPLOYER")" "$BAL_SLOT")"
rpc anvil_setStorageAt "$PWX" "$SLOT" "$(python3 -c "print(hex($RESERVE * 2).replace('0x','').rjust(64,'0'))")" >/dev/null
held="$(cast call "$PWX" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$FORK_RPC" | awk '{print $1}')"
# RESERVE * 2 in python, not $(( RESERVE * 2 )): bash arithmetic is a C long and 4e22 wei wraps inside
# it -- the assertion itself was the first thing in this rehearsal to hit that, and it "failed" by
# wanting a number that had silently become 7458848197692096512.
eq "balanceOf answers the funding through the contract's own getter" "$(python3 -c "print($RESERVE * 2)")" "$held"

# ---- the legacy-retirement gate ---------------------------------------------------------------
# Tested in BOTH directions, because a gate that always refuses proves nothing. Run only now that the
# deployer can actually pay for a window: earlier, the spendability refusal fires first and a "refused"
# result here would be the wrong guard answering.
LEGACY_SUPPLY_FORK="$(cast call "$LEGACY_WLXON" 'totalSupply()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
[ "$LEGACY_SUPPLY_FORK" != "0" ] && ok "the fork carries the real legacy supply ($(python3 -c "print('%.6f' % (int('$LEGACY_SUPPLY_FORK')/10**18))") wLXON), so this gate has something to refuse" \
  || bad "the fork's legacy supply reads 0 -- nothing for the gate to refuse, so its refusal could not be tested here"
expect "PHASE=fund refuses to open a window while the unbacked legacy supply still exists" "refusing to plan a window over" \
  env "${FUND_ENV[@]}" PLAN_DIR="$WORK/pf-gate" bash script/polygon137/PlanWlxon137.sh
expect "and it names the token by reading oldWLXON() off the migration contract, not from the arguments" "oldWLXON (read from the contract" \
  env "${FUND_ENV[@]}" PLAN_DIR="$WORK/pf-gate2" bash script/polygon137/PlanWlxon137.sh
expect "and it says out loud that the chain will not stop this, because the migration contract's ADMIN_ROLE is the deployer" "ADMIN_ROLE on the migration contract, and that role is THIS deployer" \
  env "${FUND_ENV[@]}" PLAN_DIR="$WORK/pf-gate3" bash script/polygon137/PlanWlxon137.sh
[ "$(cast call "$PM" "hasRole(bytes32,address)(bool)" "$(cast keccak 'ADMIN_ROLE')" "$DEPLOYER" --rpc-url "$FORK_RPC" | head -1)" = "true" ] \
  && ok "chain: that sentence is true -- the deployer can call startMigration with no timelock in front of it" \
  || bad "chain says the deployer is NOT the migration contract's admin, so the gate's warning text is stale"
[ "$(cast call "$PM" "hasRole(bytes32,address)(bool)" "$(cast keccak 'ADMIN_ROLE')" "$PTL" --rpc-url "$FORK_RPC" | head -1)" = "false" ] \
  && ok "chain: and the timelock THIS BATCH CREATED does not admin the migration contract -- custody of the window is the key, not the delay" \
  || bad "the timelock DOES admin the migration contract -- the gate's stated reason is wrong"
# The contrast that makes the finding precise rather than alarming: the same batch put wLXONSecure's admin
# behind the delay and the migration contract's admin in the key. Both true at once, which is why the gate
# is a planner gate and not a chain guarantee.
[ "$(cast call "$PWX" "hasRole(bytes32,address)(bool)" "$(cast keccak 'ADMIN_ROLE')" "$PTL" --rpc-url "$FORK_RPC" | head -1)" = "true" ] \
  && ok "chain: wLXONSecure's ADMIN_ROLE really is the timelock's, so the asymmetry is per-contract, not a mistake in this reading" \
  || bad "wLXONSecure's ADMIN_ROLE is not the created timelock -- the launch record's custody claim would be wrong"

# Now the pass side: zero the legacy supply the way a retirement would, and watch the gate let it through.
rpc anvil_setStorageAt "$LEGACY_WLXON" 0x0000000000000000000000000000000000000000000000000000000000000002 \
  0x0000000000000000000000000000000000000000000000000000000000000000 >/dev/null
PZ="$WORK/pf-retired"; mkdir -p "$PZ"
out="$(env PHASE=fund PLAN_DIR="$PZ" DEPLOYER="$DEPLOYER" RPC_137="$FORK_RPC" WLXON_MIGRATION_NEW="$PWX" \
  WLXON_MIGRATION="$PM" WLXON_RESERVE="$RESERVE" WLXON_MIGRATION_DAYS=30 WLXON_START_MIGRATION=1 \
  WLXON_EXPECT_CHAIN_ID=137 WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh 2>&1)"; rc=$?
printf 'plan-fund-retired rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "with the legacy supply retired, PHASE=fund plans the window WITHOUT any override" || bad "the gate refused a retired chain: $(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
echo "$out" | grep -q "legacy supply retired" && ok "and it says why it let it through"
export PLAN_DIR="$PZ"
eq "the plan records the gate as passed" "passed" "$(python3 "$LIB" field legacyRetirementGate)"
eq "the plan records the legacy token it checked, by address" "$(addr_lc "$LEGACY_WLXON")" "$(addr_lc "$(python3 "$LIB" field legacyToken)")"
eq "the plan records the supply it checked, as the chain answered it" "0" "$(python3 "$LIB" field legacySupply)"
# put the supply back so the rest of the rehearsal rehearses the world as it is on mainnet
rpc anvil_setStorageAt "$LEGACY_WLXON" 0x0000000000000000000000000000000000000000000000000000000000000002 \
  "$(python3 -c "print(hex($LEGACY_SUPPLY_FORK).replace('0x','').rjust(64,'0'))")" >/dev/null
eq "the legacy supply is restored for the rest of the run" "$LEGACY_SUPPLY_FORK" "$(cast call "$LEGACY_WLXON" 'totalSupply()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"

out="$(env "${FUND_ENV[@]}" WLXON_I_ACCEPT_LEGACY_UNRETIRED=1 bash script/polygon137/PlanWlxon137.sh 2>&1)"; rc=$?
printf 'plan-fund rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "PHASE=fund planned two transactions against the real deployed addresses (gate overridden)" || bad "PHASE=fund exited $rc" "$(printf '%s' "$out" | tail -6 | tr '\n' ' ')"
export PLAN_DIR="$P2"
eq "the override is written into the plan, not just the console" "overridden" "$(python3 "$LIB" field legacyRetirementGate)"
eq "with the supply it chose to override for" "$LEGACY_SUPPLY_FORK" "$(python3 "$LIB" field legacySupply)"
grep -q "LEGACY-RETIREMENT GATE WAS OVERRIDDEN" "$P2/MANIFEST.txt" && ok "and the manifest shouts about it in its own header"
eq "the fund batch is two transactions" "2" "$(python3 "$LIB" field txCount)"
eq "and it opens the window, recorded as a fact" "True" "$(python3 "$LIB" field opensMigrationWindow)"
fl="$(python3 "$LIB" txs | cut -f1 | tr '\n' ',')"
eq "fund moves the reserve before it opens the window" "fundReserve,startMigration," "$fl"
eq "the reserve step is paid from the wLXONSecure the deploy phase created" "$(addr_lc "$PWX")" "$(addr_lc "$(python3 "$LIB" txs | head -1 | cut -f3)")"
eq "and paid into the migration contract the deploy phase created" "$(addr_lc "$PM")" "$(addr_lc "$(cast calldata-decode "transfer(address,uint256)" "$(python3 "$LIB" txs | head -1 | cut -f5)" | head -1)")"
grep -q "OPENS THE MIGRATION WINDOW" "$P2/MANIFEST.txt" && ok "the manifest warns in its own words that this batch makes migrations claimable"
out="$(env PLAN_DIR="$P2" KEYSTORE="$KS/137deployer" PASSWORD_FILE="$WORK/pw-deploy" bash script/polygon137/SignWlxon137Plan.sh 2>&1)"; rc=$?
printf 'sign-fund rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "the key host signed the fund batch" || bad "signing the fund batch exited $rc" "$(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
out="$(env PLAN_DIR="$P2" SIGNED_DIR="$P2/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"; rc=$?
printf 'broadcast-fund rc=%s\n%s\n\n' "$rc" "$out" >> "$LOG"
[ "$rc" = 0 ] && ok "the fund batch broadcast clean" || bad "the fund broadcast exited $rc" "$(printf '%s' "$out" | tail -8 | tr '\n' ' ')"
eq "chain: the reserve is exactly what the plan moved" "$RESERVE" "$(cast call "$PM" 'reserveBalance()(uint256)' --rpc-url "$FORK_RPC" | awk '{print $1}')"
eq "chain: the window is open" "true" "$(cast call "$PM" 'migrationActive()(bool)' --rpc-url "$FORK_RPC" | head -1)"
eq "chain: the signer's new-wLXON fell by the reserve" "$RESERVE" "$(python3 -c "print($held - $(cast call "$PWX" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$FORK_RPC" | awk '{print $1}'))")"
span="$(python3 -c "
import subprocess,json
def call(sig):
    return int(subprocess.run(['cast','call','$PM',sig,'--rpc-url','$FORK_RPC'],capture_output=True,text=True).stdout.split()[0])
print(call('migrationEndTime()(uint256)') - call('migrationStartTime()(uint256)'))")"
eq "chain: the window is 30 days, not 30 blocks or 3 days" "$((30*86400))" "$span"

# ---------------------------------------------------------------- the replay gate -------------
note "single use"
expect "the same signed batch cannot be broadcast twice" "starts at" \
  env PLAN_DIR="$P2" SIGNED_DIR="$P2/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh
grep -q "This batch DOES NOT OPEN THE WINDOW" "$P1/MANIFEST.txt" && ok "the deploy plan's manifest still tells the truth about what it did"
cp "$S1/03-setOldToken.raw.hex" "$WORK/swapme"
python3 - "$S1" <<'PY'
import os, sys
d = sys.argv[1]
a = open(os.path.join(d, "03-setOldToken.raw.hex")).read()
b = open(os.path.join(d, "04-setNewToken.raw.hex")).read()
open(os.path.join(d, "03-setOldToken.raw.hex"), "w").write(b)
open(os.path.join(d, "04-setNewToken.raw.hex"), "w").write(a)
PY
expect "swapping two signed files is caught by decoding them, at the index the plan puts them at" "BAD  03-setOldToken" \
  env PLAN_DIR="$P1" SIGNED_DIR="$S1" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh
grep -q 'different step than the plan puts at nonce' script/polygon137/BroadcastWlxon137Signed.sh \
  && ok "the filename/plan pairing guard is still in the broadcaster, behind the decode check" || bad "the pairing guard is missing from the broadcaster"
cp "$WORK/setold.orig" "$S1/03-setOldToken.raw.hex"
cp "$WORK/swapme" "$S1/04-setNewToken.raw.hex" 2>/dev/null || true

# ---------------------------------------------------------------- the vendored copy check ------
note "cleanup"
rm -rf "$WORK"
[ -d "$WORK" ] && bad "the throwaway keys survived -- a rehearsal must not leave keys behind" || ok "the throwaway keystores and plans were destroyed"
echo
echo "rehearsal: $PASSED assertions passed, $FAILED failed, $SKIP skipped (log: $LOG)"
[ "$FAILED" = 0 ] || { echo "NOT GREEN -- fix before any ceremony uses these scripts."; exit 1; }
echo "GREEN: plan -> sign -> broadcast proven on a chain-137 node with a throwaway key."
