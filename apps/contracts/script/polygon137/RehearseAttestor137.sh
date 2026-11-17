#!/usr/bin/env bash
# Rehearse the addAttestor timelock ceremony against a chain-137 FORK, end to end, and fail loudly if any
# link in the plan -> sign -> broadcast -> wait-48h -> execute chain is not what the runbook claims.
#
#   UPSTREAM=https://polygon-bor-rpc.publicnode.com KEYSTORE=~/.lxon/keystores/polygon-137 \
#   PASSWORD_FILE=~/.lxon/secrets/polygon-137.pw bash script/polygon137/RehearseAttestor137.sh
#
# This is not a rehearsal of the launch ceremony (RehearseWlxon137.sh did that). It rehearses the part the
# launch deliberately left undone: ADMIN_ROLE belongs to the TimelockController, so registering an attestor
# is two transactions forty-eight hours apart, and the second one only works if the first produced exactly
# the proposal id the second names.
#
# What it proves, in order:
#   * the fork is a fork -- the deployer is topped up to a balance mainnet has never shown it. A rehearsal
#     that cannot tell itself apart from the real chain is a launch.
#   * the deployer genuinely cannot addAttestor directly (the chain says AccessControlUnauthorizedAccount),
#     so the timelock is not decoration;
#   * schedule() mines, and getTimestamp(id) lands at least minDelay after the block that mined it;
#   * executing early is refused by the PLANNER, not by the chain alone -- the plan is what would have
#     authorised it;
#   * the proposal id both legs use is the contract's own hashOperation output, not a local keccak;
#   * after the delay, execute() mines and hasRole(ATTESTOR_ROLE, attestor) flips to true on wLXONSecure,
#     the deployer still holds no ATTESTOR_ROLE, and totalSupply is still 0 with quorum 2 -- one attestor
#     mints nothing;
#   * a tampered signature is refused by the broadcaster before anything is published.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FORK_PORT="${FORK_PORT:-8548}"
FORK_RPC="${FORK_RPC:-http://127.0.0.1:$FORK_PORT}"
UPSTREAM="${UPSTREAM:-https://polygon-bor-rpc.publicnode.com}"
D=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
PWX=0xD69fB341F35cadE285331797D7d35c5613D7Dfbe
PTL=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054
A="${REHEARSE_ATTESTOR:-0xf00dc0ffee000000000000000000000000000001}"
REAL_A="${ATTESTOR:-0x283697339fC32e286951D9F94Fa64082142cBC37}"
KS="${KEYSTORE:?usage: KEYSTORE=<the 137 keystore> PASSWORD_FILE=<pw file> bash script/polygon137/RehearseAttestor137.sh}"
PW="${PASSWORD_FILE:?usage: PASSWORD_FILE=<file holding the keystore password>}"
# Out of the environment the moment they are local variables. Both the planner and the broadcaster refuse
# a key on principle, and an exported KEYSTORE inherited by every `env ...` child in this script would
# make each of those refusals fire for the wrong reason -- the guard tests would then be proving that the
# guard exists, not that it catches what it is meant to catch.
unset KEYSTORE PASSWORD_FILE

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
say() { printf '\n== %s\n' "$1"; }
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
rpcv(){ cast rpc "$@" --rpc-url "$FORK_RPC" 2>&1 | tr -d '"'; }
rd()  { cast call "$1" "$2" "${@:3}" --rpc-url "$FORK_RPC" 2>/dev/null | head -1; }

WORK="$(mktemp -d /tmp/att137-rehearse-XXXXXX)"
ANVIL_PID=""
cleanup() {
  [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

say "fork"
# Fork at the head by default, because the public chain-137 RPCs are not archive nodes: asking for a block
# ~100 behind head died with "failed to create genesis: historical state … is not available" (measured
# 2026-10-27). FORK_BLOCK is left as an override for whoever runs this against an archive endpoint.
#
# Rehearsing against the head means the fork already contains the queue transaction this script rehearses
# (block 96,231,298). That is why REHEARSE_ATTESTOR below is a stand-in address rather than attestor-mac:
# the ceremony being proved is the mechanism -- queue, wait, execute -- and a mechanism test must not depend
# on the one proposal that already used it. The real address is still exercised, as the case the planner
# must REFUSE because it is already pending.
FORK_BLOCK="${FORK_BLOCK:-}"
if [ -z "$FORK_BLOCK" ]; then
  FORK_BLOCK="$(python3 -c "print(int('$(cast rpc eth_blockNumber --rpc-url "$UPSTREAM" 2>/dev/null | tr -d '"')',16))")"
fi
[ -n "$FORK_BLOCK" ] || { bad "$UPSTREAM did not answer eth_blockNumber -- nothing to fork"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
anvil --fork-url "$UPSTREAM" --fork-block-number "$FORK_BLOCK" --fork-chain-id 137 --port "$FORK_PORT" --auto-impersonate \
  >"$WORK/anvil.log" 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 60); do cast rpc eth_chainId --rpc-url "$FORK_RPC" >/dev/null 2>&1 && break; sleep 1; done
eq "137" "$(python3 -c "print(int('$(rpcv eth_chainId)',16))")" "the fork answers chain id 137, so WLXON_EXPECT_CHAIN_ID cannot quietly be wrong"
# Compared against the artifact this repo compiles, not against a length typed into this file. A hardcoded
# hex count was wrong by two as soon as it was written, because the quotes around cast's answer are not
# part of the bytecode -- and "the fork has some code" proves nothing; "the fork has THE code" is the claim.
# The comparison cannot be a bare equality, and finding that out is worth more than an ok line: wLXONSecure
# holds immutables (nativeLXON, sourceChainId 724, targetChainId 137), which solc leaves as ZERO PADDING in
# the artifact's deployedBytecode and fills at deploy time. So the rule is: same length, and every byte
# that differs must be padding in the artifact. Then the deployed code is the compiled code plus its
# constructor arguments -- nothing more. OZ's TimelockController has no immutables, so it matches exactly.
assert_code() { # address artifact-name label  expected-immutable-hex(optional, comma list)
  local want got npad
  want="$(python3 -c "import json,glob;print(json.load(open(glob.glob('artifacts/**/$2.sol/$2.json',recursive=True)[0]))['deployedBytecode'].lower().replace('0x',''))")"
  got="$(rpcv eth_getCode "$1" latest | tr -d '"' | tr -d '\n' | tr 'A-Z' 'a-z' | sed 's/^0x//')"
  npad="$(python3 - "$want" "$got" <<'PY'
import sys
w, g = sys.argv[1], sys.argv[2]
if len(w) != len(g):
    print("LENGTH artifact %d hex vs deployed %d hex" % (len(w), len(g))); sys.exit(0)
diff = [k for k in range(len(w)) if w[k] != g[k]]
if not diff:
    print("identical"); sys.exit(0)
# A difference is only acceptable where the artifact holds zero padding for an immutable.
bad = [k for k in diff if w[k] != '0']
if bad:
    print("REAL DIFFERENCE at bytes %s" % sorted(set(k // 2 for k in bad))[:12]); sys.exit(0)
slots = sum(1 for i, k in enumerate(diff) if i == 0 or k - diff[i - 1] > 1)
print("PADDING %d immutable slots, %d bytes filled by the constructor (%d bytes total)"
      % (slots, len(diff), len(w) // 2))
PY
)"
  case "$npad" in
    PADDING*)   ok "$3 -- ${npad#PADDING }" ;;
    identical)  ok "$3 -- deployed bytecode equals the compiled artifact byte for byte" ;;
    LENGTH*)    bad "$3: $npad" ;;
    *)          bad "$3: the deployed code is not this build ($npad)" ;;
  esac
}
assert_code "$PWX" wLXONSecure "wLXONSecure on this fork is the bytecode this repo compiles"
assert_code "$PTL" TimelockController "the timelock on this fork is OpenZeppelin's compiled TimelockController"
rpcv anvil_setBalance "$D" 0x152d02c7e14af6800000 >/dev/null
bal="$(python3 -c "print(int('$(rpcv eth_getBalance $D latest)',16)//10**18)")"
if [ "$bal" -ge 100 ] 2>/dev/null; then ok "this is a fork, not Polygon: $D shows ${bal} POL (mainnet holds 17.005508)"
else bad "the fork did not top up the deployer (${bal} POL) -- refuse to continue, a real-chain balance means a real-chain broadcast"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; fi

say "custody as the chain states it"ADMIN_ID="$(rd "$PWX" 'ADMIN_ROLE()(bytes32)')"
AT_ID="$(rd "$PWX" 'ATTESTOR_ROLE()(bytes32)')"
eq "$ADMIN_ID" "$(cast keccak 'ADMIN_ROLE')" "ADMIN_ROLE id matches keccak(\"ADMIN_ROLE\")"
eq "true" "$(rd "$PWX" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" "$(lc "$PTL")")" "ADMIN_ROLE belongs to the timelock"
eq "false" "$(rd "$PWX" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" "$(lc "$D")")" "ADMIN_ROLE does not belong to the deployer"
eq "false" "$(rd "$PWX" "hasRole(bytes32,address)(bool)" "$AT_ID" "$(lc "$A")")" "the attestor starts unregistered"
eq "2" "$(rd "$PWX" 'quorum()(uint256)' | awk '{print $1}')" "quorum is 2"
eq "172800" "$(rd "$PTL" 'getMinDelay()(uint256)' | awk '{print $1}')" "the timelock's minDelay is 48 h"
eq "true" "$(rd "$PTL" "hasRole(bytes32,address)(bool)" "$(cast keccak 'PROPOSER_ROLE')" "$(lc "$D")")" "the deployer holds PROPOSER_ROLE"
eq "true" "$(rd "$PTL" "hasRole(bytes32,address)(bool)" "$(cast keccak 'EXECUTOR_ROLE')" "$(lc "$D")")" "the deployer holds EXECUTOR_ROLE"
INNER="$(cast calldata 'addAttestor(address)' "$A")"
Z32=0x0000000000000000000000000000000000000000000000000000000000000000
PID="$(cast call "$PTL" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' "$(lc "$PWX")" 0 "$INNER" "$Z32" "$Z32" --rpc-url "$FORK_RPC" | head -1)"
eq "0" "$(rd "$PTL" 'getOperationState(bytes32)(uint8)' "$PID" | awk '{print $1}')" "this fork is a world where the queue tx has not happened (proposal state Unset) -- if this fails, FORK_BLOCK names a block after 96,231,298 and the rehearsal is testing a chain that already did it"
direct="$(cast rpc eth_estimateGas "{\"from\":\"$(lc "$D")\",\"to\":\"$(lc "$PWX")\",\"data\":\"$(cast calldata 'addAttestor(address)' "$A")\"}" --rpc-url "$FORK_RPC" 2>&1)"
case "$direct" in
  *revert*AccessControl*|*revert*": custom error"*|*"execution reverted"*) ok "chain: the deployer's OWN addAttestor call is refused -- the timelock is not decoration" ;;
  *) bad "the deployer's direct addAttestor did NOT revert ($direct); ADMIN_ROLE would be usable without a delay" ;;
esac

PLANENV=(RPC_137="$FORK_RPC" DEPLOYER="$D" WLXON_ADDR="$PWX" TIMELOCK_ADDR="$PTL"
         ATTESTOR="$A" WLXON_I_ACCEPT_MAINNET_RISK=1)

say "planner refusals (nothing signed, nothing broadcast)"
t="$WORK/pk"; mkdir -p "$t"
out="$(env PRIVATE_KEY=0x$(printf '11%.0s' {1..64}) PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "PRIVATE_KEY" && ok "refuses to plan with PRIVATE_KEY set" || bad "planned with a key in the environment: $out"
t="$WORK/ks"; mkdir -p "$t"
out="$(env KEYSTORE="$KS" PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses to plan with KEYSTORE set (the key host signs, the planner does not)" || bad "planned while holding a keystore path"
t="$WORK/noack"; mkdir -p "$t"
out="$(env PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" WLXON_I_ACCEPT_MAINNET_RISK= bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "MAINNET" && ok "refuses a chain-137 plan without WLXON_I_ACCEPT_MAINNET_RISK=1" || bad "planned mainnet without the risk acknowledgement: $out"
t="$WORK/zero"; mkdir -p "$t"
out="$(env PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" ATTESTOR=0x0000000000000000000000000000000000000000 bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses the zero attestor" || bad "planned addAttestor(0x0)"
t="$WORK/self"; mkdir -p "$t"
out="$(env PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" ATTESTOR="$D" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "separate hosts" && ok "refuses to register the signing key itself as its own attestor" || bad "planned attestor == deployer: $out"
t="$WORK/sig"; mkdir -p "$t"
out="$(env PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" ADMIN_SIG='addAttestor(address,uint256)' bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses an admin signature the artifact does not expose" || bad "planned a signature wLXONSecure does not have: $out"
t="$WORK/early"; mkdir -p "$t"
out="$(env PHASE=execute PLAN_DIR="$t" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "nothing is scheduled" && ok "refuses to plan an execute for a proposal that was never queued" || bad "planned an execute with nothing scheduled: $out"
# The proposal this ceremony actually put on chain (block 96,231,298) is Queued on every fork of a head
# after it, so re-planning THAT one is the paid no-op the guard exists for. Skipped, and said out loud, if
# someone runs this against an archive node pinned below that block.
real_state="$(rd "$PTL" 'getOperationState(bytes32)(uint8)' "$(cast call "$PTL" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' "$(lc "$PWX")" 0 "$(cast calldata 'addAttestor(address)' "$REAL_A")" "$Z32" "$Z32" --rpc-url "$FORK_RPC" | head -1)" | awk '{print $1}')"
if [ "$real_state" = "0" ]; then
  ok "this fork ($FORK_BLOCK) predates the real queue tx, so the already-pending case cannot be tested here -- say so rather than pretending it passed"
else
  t="$WORK/pending"; mkdir -p "$t"
  out="$(env PHASE=schedule PLAN_DIR="$t" "${PLANENV[@]}" ATTESTOR="$REAL_A" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE "not Unset|already holds ATTESTOR_ROLE" \
    && ok "refuses to queue the attestor-mac ceremony a second time (chain state $real_state) -- the 2026-10-27 mainnet proposal is protected from a repeat" \
    || bad "planned a duplicate of the live proposal (state $real_state): $out"
fi

say "PHASE=schedule"
P1="$WORK/sched"; mkdir -p "$P1"
out="$(env PHASE=schedule PLAN_DIR="$P1" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)" || { bad "the schedule planner failed:"; printf '%s\n' "$out"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | sed 's/^/    /'
pid1="$(python3 -c "import json;print(json.load(open('$P1/plan.json'))['proposalId'])")"
n0="$(python3 -c "import json;print(json.load(open('$P1/plan.json'))['startNonce'])")"
eq "$n0" "$(python3 -c "print(int('$(rpcv eth_getTransactionCount $(lc "$D") latest)',16))")" "the plan's start nonce is the chain's nonce right now"
INNER="$(cast calldata 'addAttestor(address)' "$A")"
eq "$pid1" "$PID" "the id in the plan equals the contract's own hashOperation for this call"
txd="$(python3 -c "import json;print(json.load(open('$P1/plan.json'))['txs'][0]['data'])")"
eq "0x01d5062a" "${txd:0:10}" "the scheduled transaction calls schedule(...) on the timelock"
printf '%s' "$txd" | grep -qi "${A#0x}" && ok "the attestor address is inside the queued calldata" || bad "the attestor address is not in the payload"

say "sign"
out="$(env PLAN_DIR="$P1" KEYSTORE="$KS" PASSWORD_FILE="$PW" bash script/polygon137/SignWlxon137Plan.sh 2>&1)" || { bad "the signer refused:"; printf '%s\n' "$out"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | grep -E '^  OK' | sed 's/^/    /'
ls "$P1/signed"/00-schedule*.raw.hex >/dev/null 2>&1 && ok "one signed transaction, labelled 00-schedule" || bad "no 00-schedule signature file"

say "tamper check (flip one byte, the broadcaster must refuse before publishing)"
cp -R "$P1/signed" "$WORK/tampered"
f="$(ls "$WORK"/tampered/00-*.raw.hex | head -1)"
python3 - "$f" <<'PY'
import sys
p=sys.argv[1]; h=open(p).read().strip()
b=bytearray.fromhex(h)
b[-8]^=0x01
open(p,'w').write(b.hex())
PY
out="$(env PLAN_DIR="$P1" SIGNED_DIR="$WORK/tampered" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "a tampered signature is refused" || bad "the broadcaster accepted a tampered signature: $out"
printf '%s' "$out" | grep -q "did not accept\|does not match\|BAD\|FATAL" && ok "it says so explicitly rather than publishing it" || bad "refusal without a reason"
nonce_after_tamper="$(python3 -c "print(int('$(rpcv eth_getTransactionCount $(lc "$D") latest)',16))")"
eq "$n0" "$nonce_after_tamper" "the tampered run moved no nonce -- nothing was published"

say "broadcast"
out="$(env PLAN_DIR="$P1" SIGNED_DIR="$P1/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)" || { bad "the broadcast failed:"; printf '%s\n' "$out"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | sed -n '/Read-back/,$p' | sed 's/^/    /'
nonce_now="$(python3 -c "print(int('$(rpcv eth_getTransactionCount $(lc "$D") latest)',16))")"
eq "1" "$(python3 -c "print($nonce_now - $n0)")" "exactly one nonce was spent"
eq "1" "$(rd "$PTL" 'getOperationState(bytes32)(uint8)' "$pid1" | awk '{print $1}')" "state(id) is Waiting (1) on chain -- OZ 5.6.1's enum is {Unset, Waiting, Ready, Done}; there is no Cancelled value, a killed proposal reads 3 like a done one"
eq "false" "$(rd "$PTL" 'isOperationReady(bytes32)(bool)' "$pid1")" "and not yet ready"
eta="$(python3 -c "print($(rd "$PTL" 'getTimestamp(bytes32)(uint256)' "$pid1" | awk '{print $1}'))")"
mine_blk="$(python3 -c "import json;print(json.load(open('$P1/launch-record.json'))['steps'][0]['block'])")"
mine_ts="$(cast rpc eth_getBlockByNumber "$(python3 -c "print(hex($mine_blk))")" false --rpc-url "$FORK_RPC" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16))')"
if [ "$eta" -ge "$((mine_ts + 172800))" ]; then ok "eta $eta is at least minDelay after the block that scheduled it ($mine_ts) -- the 48 h is the chain's, not the script's"
else bad "eta $eta is before mine+172800 ($mine_ts): the delay would be skippable"; fi

say "the planner refuses an early execute (the chain would too)"
P2="$WORK/exec-early"; mkdir -p "$P2"
out="$(env PHASE=execute PLAN_DIR="$P2" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "delay has not elapsed" && ok "PHASE=execute before the delay is refused, with the time it becomes ready named" || bad "planned an execute before the delay: $out"
P2b="$WORK/double"; mkdir -p "$P2b"
out="$(env PHASE=schedule PLAN_DIR="$P2b" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "not Unset" && ok "a second schedule of the same pending operation is refused (no paid no-op)" || bad "queued the same proposal twice: $out"

say "warp past the delay and execute"
rpcv evm_increaseTime 172801 >/dev/null; rpcv evm_mine >/dev/null
eq "true" "$(rd "$PTL" 'isOperationReady(bytes32)(bool)' "$pid1")" "state flips to Ready after the delay"
P3="$WORK/exec"; mkdir -p "$P3"
out="$(env PHASE=execute PLAN_DIR="$P3" "${PLANENV[@]}" bash script/polygon137/PlanAttestor137.sh 2>&1)" || { bad "the execute planner refused a ready proposal:"; printf '%s\n' "$out"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | sed 's/^/    /'
pid2="$(python3 -c "import json;print(json.load(open('$P3/plan.json'))['proposalId'])")"
eq "$pid1" "$pid2" "the execute leg names the SAME proposal id the schedule leg queued"
out2="$(env PLAN_DIR="$P3" KEYSTORE="$KS" PASSWORD_FILE="$PW" bash script/polygon137/SignWlxon137Plan.sh 2>&1)" || { bad "the signer refused the execute leg:"; printf '%s\n' "$out2"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out2" | grep -E '^  OK' | sed 's/^/    /'
out3="$(env PLAN_DIR="$P3" SIGNED_DIR="$P3/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)" || { bad "the execute broadcast failed:"; printf '%s\n' "$out3"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out3" | sed -n '/Read-back/,$p' | sed 's/^/    /'
eq "true" "$(rd "$PWX" "hasRole(bytes32,address)(bool)" "$AT_ID" "$(lc "$A")")" "chain: the attestor now holds ATTESTOR_ROLE"
eq "false" "$(rd "$PWX" "hasRole(bytes32,address)(bool)" "$AT_ID" "$(lc "$D")")" "chain: the deployer holds no ATTESTOR_ROLE (it cannot attest its own claims)"
eq "3" "$(rd "$PTL" 'getOperationState(bytes32)(uint8)' "$pid1" | awk '{print $1}')" "state(id) is Done (3) -- and the next line is what makes 3 mean executed rather than cancelled"
eq "0" "$(rd "$PWX" 'totalSupply()(uint256)' | awk '{print $1}')" "totalSupply is still 0 -- one attestor with quorum 2 mints nothing"
eq "2" "$(rd "$PWX" 'quorum()(uint256)' | awk '{print $1}')" "quorum is still 2 -- this ceremony did not quietly lower it"
inner_after="$(cast rpc eth_estimateGas "{\"from\":\"$(lc "$D")\",\"to\":\"$(lc "$PWX")\",\"data\":\"$INNER\"}" --rpc-url "$FORK_RPC" 2>&1)"
case "$inner_after" in *revert*) ok "the deployer still cannot call addAttestor directly after all of this" ;; *) bad "direct addAttestor now succeeds -- ADMIN_ROLE leaked to the signer" ;; esac

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1
