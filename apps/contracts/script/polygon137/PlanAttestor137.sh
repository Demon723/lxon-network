#!/usr/bin/env bash
# Plan ONE timelock-gated admin call on Polygon 137 -- queue it, or execute it once it is due -- without
# touching a key.
#
#   PHASE=schedule PLAN_DIR=/tmp/att-sched DEPLOYER=0x… ATTESTOR=0x… \
#   WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAttestor137.sh
#
#   PHASE=execute  PLAN_DIR=/tmp/att-exec DEPLOYER=0x… ATTESTOR=0x… \
#   WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAttestor137.sh
#
# Why this exists as a third planner: wLXONSecure gave ADMIN_ROLE to the TimelockController this batch
# created, so the deployer who signed the launch CANNOT call addAttestor, setQuorum, pauseBridge or
# emergencyWithdraw directly. Measured on chain 137 (2026-10-27): eth_estimateGas of
# addAttestor(deployer) from the deployer reverts with AccessControlUnauthorizedAccount(0x2a8Ca0…,
# ADMIN_ROLE). Every admin change is therefore two transactions, forty-eight hours apart, and each one
# goes through the same plan -> sign -> broadcast split as the launch:
#
#   PHASE=schedule  timelock.schedule(target, 0, data, 0x0, 0x0, minDelay)   -- nonce N
#   ... 48 h, the delay is the whole point ...
#   PHASE=execute   timelock.execute(target, 0, data, 0x0, 0x0)               -- nonce N+1
#
# The execute leg is planned and signed when it is DUE, not in advance: Polygon's base fee moved between
# 2.3 and 248 gwei on the day this was written, so a signature priced today would still be priced at
# today's floor tomorrow, and a maxFee under tomorrow's base fee is a transaction that cannot be
# included. Re-planning costs one RPC call; a stranded signature costs the ceremony.
#
# The salt is zero, deliberately: hashOperation(target, value, data, predecessor, salt) is a pure view,
# so with salt 0 the proposal id is fully determined by the call itself and both legs -- and anyone
# auditing later -- compute the same bytes32 without a note saying which random salt was used. The cost
# is that the identical operation cannot be queued twice at once, which is a feature: a second schedule
# of the same pending addAttestor is a paid no-op.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="script/polygon137/lib/offline_plan1559.py"
PLAN_LIB="script/polygon137/lib/plan137.py"

die() { echo "FATAL: $*" >&2; [ -n "${CREATED_PLAN_DIR:-}" ] && [ "$CREATED_PLAN_DIR" = "${PLAN_DIR:-}" ] \
  && echo "       ($PLAN_DIR holds whatever this run wrote before it stopped -- use a new directory next time)" >&2
  exit 1; }
CREATED_PLAN_DIR=""
say() { printf '  %s\n' "$*"; }
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
addr_guard() {
  printf '%s' "$1" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "$2=$1 is not a 20-byte address"
  [ "$(lc "$1")" != "0x0000000000000000000000000000000000000000" ] || die "$2 is the zero address"
  case "$(lc "$1")" in
    0x00000000000000000000000000000000000000*|0x11111111111111111111111111111111111111*|0xdead0000000000000000000000000000000000*)
      die "$2=$1 looks like a placeholder. Nothing is planned against a placeholder." ;;
  esac
}
has_code() { local c; c="$(cast rpc eth_getCode "$1" latest --rpc-url "$RPC_137" 2>/dev/null | tr -d '"' || true)"
             [ -n "$c" ] && [ "$c" != "0x" ]; }
estimate() { local json est
  json="{\"from\":\"$(lc "$DEPLOYER")\",\"to\":\"$1\",\"data\":\"$2\"}"
  est="$(cast rpc eth_estimateGas "$json" --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
  [ -n "$est" ] || return 1
  python3 -c "print(int('$est',16) * 115 // 100)"
}
rd() { cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_137" 2>/dev/null | head -1; }

PHASE="${PHASE:?usage: PHASE=schedule|execute PLAN_DIR=<new dir> DEPLOYER=0x… ATTESTOR=0x… bash script/polygon137/PlanAttestor137.sh}"
DEPLOYER="${DEPLOYER:?usage: DEPLOYER=<the 137 address that signs -- it must hold PROPOSER_ROLE (schedule) or EXECUTOR_ROLE (execute)>}"
PLAN_DIR="${PLAN_DIR:?usage: PLAN_DIR=<new dir>}"
RPC_137="${RPC_137:-https://polygon-bor-rpc.publicnode.com}"
EXPECT_CHAIN="${WLXON_EXPECT_CHAIN_ID:-137}"
case "$PHASE" in schedule|execute) ;; *) die "PHASE must be schedule or execute (got $PHASE)" ;; esac

# No key here, same refusal as the launch planner. A planner that can sign collapses the split back into
# one machine holding both the plan and the secret.
[ -z "${PRIVATE_KEY:-}" ] || die "PLAN mode needs no key. PRIVATE_KEY= is refused here on purpose -- unset it."
[ -z "${KEYSTORE:-}" ]    || die "PLAN mode needs no keystore; SignWlxon137Plan.sh is the script that uses one."
[ -z "${PASSWORD_FILE:-}" ] || die "PLAN mode needs no password file either."
printf '%s' "$DEPLOYER" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "DEPLOYER=$DEPLOYER is not a 20-byte address"

# ---- which call this ceremony makes -------------------------------------------------------------
# Defaults to registering an attestor, because that is the step the launch left undone and the one every
# later mint depends on. The general shape (any ADMIN_ROLE function of wLXONSecure) is here so setQuorum,
# addRelayer and pauseBridge are not planned by hand-copied hex the next time someone needs them.
ADMIN_TARGET="${WLXON_ADDR:-}"
TIMELOCK="${TIMELOCK_ADDR:-}"
if [ -z "$ADMIN_TARGET" ] || [ -z "$TIMELOCK" ]; then
  rec="deployments/wlxonsecure-chain-137.json"
  [ -f "$rec" ] || die "WLXON_ADDR and TIMELOCK_ADDR are not set and $rec does not exist. Point them at the deployed contracts; do not retype addresses from notes."
  ADMIN_TARGET="${ADMIN_TARGET:-"$(python3 -c "import json;print(json.load(open('$rec'))['contracts']['wLXONSecure'])")"}"
  TIMELOCK="${TIMELOCK:-"$(python3 -c "import json;print(json.load(open('$rec'))['contracts']['TimelockController'])")"}"
fi
addr_guard "$ADMIN_TARGET" WLXON_ADDR
addr_guard "$TIMELOCK" TIMELOCK_ADDR

ADMIN_SIG="${ADMIN_SIG:-addAttestor(address)}"
ADMIN_ARGS="${ADMIN_ARGS:-${ATTESTOR:?usage: ATTESTOR=<the attestor address to register> (or set ADMIN_SIG/ADMIN_ARGS for another admin call)}}"
# The signature must exist in the artifact the repo compiles, or the calldata would fall into a fallback
# and spend the whole gas limit saying nothing.
python3 "$PLAN_LIB" calltypes wLXONSecure "$ADMIN_SIG" >/dev/null \
  || die "$ADMIN_SIG is not a function of the compiled wLXONSecure artifact"
# Every argument that claims to be an address is held to addr_guard; a number (setQuorum's argument) is
# not an address and must not be rejected for lacking 0x. The default ceremony is addAttestor, whose one
# argument is exactly an address, so the placeholder check always runs for what this script exists to do.
for a in $ADMIN_ARGS; do
  case "$a" in
    0x*) addr_guard "$a" ATTESTOR ;;
    *[!0-9]*) die "ADMIN_ARGS token $a is neither an address nor a number -- refuse to encode it as anything" ;;
  esac
done

# ---- the chain, before anything is measured against it ------------------------------------------
got_chain="$(cast rpc eth_chainId --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$got_chain" ] || die "$RPC_137 did not answer eth_chainId"
CHAIN="$(python3 -c "print(int('$got_chain',16))")"
[ "$CHAIN" = "$EXPECT_CHAIN" ] || die "$RPC_137 reports chain $CHAIN and this run is guarded for $EXPECT_CHAIN."
if [ "$CHAIN" = "137" ] && [ "${WLXON_I_ACCEPT_MAINNET_RISK:-}" != "1" ]; then
  die "chain 137 is Polygon MAINNET and this batch moves a live bridge's admin set. Set WLXON_I_ACCEPT_MAINNET_RISK=1, or rehearse against a local 137 fork first (script/polygon137/RehearseAttestor137.sh)."
fi

has_code "$(lc "$ADMIN_TARGET")" || die "no code at wLXONSecure $ADMIN_TARGET on chain $CHAIN -- this plan would queue a call to an address that cannot answer it"
has_code "$(lc "$TIMELOCK")"    || die "no code at the timelock $TIMELOCK on chain $CHAIN -- ADMIN_ROLE would belong to something that cannot hold a delay"

if [ -e "$PLAN_DIR" ] && [ -n "$(ls -A "$PLAN_DIR" 2>/dev/null || true)" ]; then
  die "$PLAN_DIR is not empty. A plan mixed with an earlier run's txs.jsonl is a batch whose nonces describe two ceremonies."
fi
mkdir -p "$PLAN_DIR"; CREATED_PLAN_DIR="$PLAN_DIR"; : > "$PLAN_DIR/txs.jsonl"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- nonce and fees, exactly as the launch planner measures them --------------------------------
p0="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
pp="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" pending --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$p0" ] || die "cannot read $DEPLOYER's nonce on chain $CHAIN"
[ "$p0" = "$pp" ] || die "$DEPLOYER has a transaction in flight (latest $p0, pending $pp); wait for it and re-plan."
START_NONCE="$(python3 -c "print(int('$p0',16))")"
PRIORITY="${MAX_PRIORITY_FEE:-}"
[ -n "$PRIORITY" ] || PRIORITY="$(cast rpc eth_maxPriorityFeePerGas --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$PRIORITY" ] || { sug="$(cast rpc eth_gasPrice --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"; PRIORITY="${sug:-0x1}"; }
PRIORITY="$(python3 -c "print(int('$PRIORITY',16))")"
BASE="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC_137" 2>/dev/null | python3 -c 'import sys,json;b=json.load(sys.stdin);b=b.get("result",b);print(int(b.get("baseFeePerGas","0x0"),16))' 2>/dev/null || echo '')"
if [ -n "${MAX_FEE:-}" ]; then
  MAXFEE="$MAX_FEE"
  [ -z "$BASE" ] || [ "$MAXFEE" -ge "$(( BASE + PRIORITY ))" ] || die "MAX_FEE=$MAXFEE is below base $BASE plus tip $PRIORITY."
  FEE_SOURCE="override"
else
  MAXFEE="$(python3 -c "print(2*(${BASE:-$PRIORITY} + $PRIORITY))")"
  FEE_SOURCE="2x live base+tip"
fi
BAL="$(cast rpc eth_getBalance "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
BAL="$(python3 -c "print(int('${BAL:-0x0}',16))")"

# ---- custody: ask the chain, do not assume -----------------------------------------------------
ADMIN_ID="$(rd "$ADMIN_TARGET" 'ADMIN_ROLE()(bytes32)')"
AT_ID="$(rd "$ADMIN_TARGET" 'ATTESTOR_ROLE()(bytes32)')"
QUORUM="$(rd "$ADMIN_TARGET" 'quorum()(uint256)' | awk '{print $1}')"
MIN_DELAY="$(rd "$TIMELOCK" 'getMinDelay()(uint256)' | awk '{print $1}')"
PROPOSER_ID="$(cast keccak 'PROPOSER_ROLE')"; EXECUTOR_ID="$(cast keccak 'EXECUTOR_ROLE')"
HOLDS_ADMIN="$(rd "$ADMIN_TARGET" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" "$(lc "$TIMELOCK")")"
[ "$HOLDS_ADMIN" = "true" ] || die "ADMIN_ROLE on $ADMIN_TARGET does not belong to $TIMELOCK (chain says $HOLDS_ADMIN). Then either the timelock is the wrong address, in which case this queue achieves nothing, or the deployer still holds admin itself -- in which case use it directly and do not spend 48 hours pretending otherwise."
DELAY="${TIMELOCK_DELAY:-$MIN_DELAY}"
[ -n "$DELAY" ] || die "the timelock did not answer getMinDelay()"
[ "$DELAY" -ge "$MIN_DELAY" ] || die "TIMELOCK_DELAY=$DELAY is under this timelock's minDelay $MIN_DELAY -- schedule() would revert with TimelockInsufficientDelay and the nonce would be spent on a failure."

say "chain $CHAIN via $RPC_137 (phase $PHASE)"
say "admin target $ADMIN_TARGET   timelock $TIMELOCK (minDelay $DELAY s = $(( DELAY / 3600 )) h)"
say "signer $DEPLOYER  nonce $START_NONCE (latest == pending)  balance $BAL wei POL"
say "gas    tip $PRIORITY wei ($(( PRIORITY / 1000000000 )) gwei), maxFee $MAXFEE wei ($FEE_SOURCE; base ${BASE:-n/a})"
say "call   $ADMIN_SIG $ADMIN_ARGS   [quorum $QUORUM, ATTESTOR_ROLE $AT_ID]"

# ---- the role the SIGNER needs for THIS leg ------------------------------------------------------
need_role_id="$PROPOSER_ID"; need_role="PROPOSER_ROLE"
[ "$PHASE" = "execute" ] && { need_role_id="$EXECUTOR_ID"; need_role="EXECUTOR_ROLE"; }
holds="$(rd "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$need_role_id" "$(lc "$DEPLOYER")")"
[ "$holds" = "true" ] || die "$DEPLOYER does not hold $need_role on the timelock (chain says $holds). This leg would revert with TimelockUnauthorizedCaller after burning its gas; grant the role through the timelock first -- which is itself a 48 h proposal."

# ---- attestor-specific: the two ways this ceremony is pointless --------------------------------
already="$(rd "$ADMIN_TARGET" "hasRole(bytes32,address)(bool)" "$AT_ID" "$(lc "$ADMIN_ARGS")")"
if [ "$PHASE" = "schedule" ] && [ "$already" = "true" ]; then
  die "$ADMIN_ARGS already holds ATTESTOR_ROLE on chain $CHAIN. Queuing addAttestor again is 48 hours and two transactions for _grantRole of a role it holds -- nothing changes. If the intent was a SECOND attestor, pass that address."
fi
if [ "$(lc "$ADMIN_ARGS")" = "$(lc "$DEPLOYER")" ]; then
  say "NOTE: the attestor being registered IS the deployer/executor key. The contract's own doc says keys must"
  say "      live on separate hosts; one key that relays, proposes, executes and attests is that key with a"
  say "      longer name. Refusing this is WLXON_I_ACCEPT_ATTESTOR_IS_DEPLOYER=1."
  [ "${WLXON_I_ACCEPT_ATTESTOR_IS_DEPLOYER:-}" = "1" ] || die "set WLXON_I_ACCEPT_ATTESTOR_IS_DEPLOYER=1 to plan it deliberately, or pass an address whose key lives elsewhere"
fi

# ---- encode, and let the contract compute the proposal id ----------------------------------------
DATA="$(cast calldata "$ADMIN_SIG" "$ADMIN_ARGS")"
back="$(cast calldata-decode "$ADMIN_SIG" "$DATA" 2>&1 | head -1 || true)"
case "$back" in *Error*|*"could not"*) die "the calldata this script produced does not decode as $ADMIN_SIG: $back" ;; esac
Z32=0x0000000000000000000000000000000000000000000000000000000000000000
SCHED="$(cast calldata 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)' "$(lc "$ADMIN_TARGET")" 0 "$DATA" "$Z32" "$Z32" "$DELAY")"
EXEC="$(cast calldata 'execute(address,uint256,bytes,bytes32,bytes32)' "$(lc "$ADMIN_TARGET")" 0 "$DATA" "$Z32" "$Z32")"
# The id comes from the contract's own pure function, not from a local keccak this script believes: if the
# two legs ever disagree about which bytes32 names this proposal, the queue would sit ready forever and
# the execute would revert on an id that was never scheduled.
PROPOSAL_ID="$(cast call "$TIMELOCK" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' "$(lc "$ADMIN_TARGET")" 0 "$DATA" "$Z32" "$Z32" --rpc-url "$RPC_137" | head -1)"
printf '%s' "$PROPOSAL_ID" | grep -Eq '^0x[0-9a-fA-F]{64}$' || die "hashOperation gave no bytes32 for this operation"
say "proposal $PROPOSAL_ID"

if [ "$PHASE" = "schedule" ]; then
  state="$(rd "$TIMELOCK" 'getOperationState(bytes32)(uint8)' "$PROPOSAL_ID" | awk '{print $1}')"
  [ "${state:-0}" = "0" ] || die "this proposal is not Unset on chain (OZ 5.6.1 OperationState: $state -- 0 Unset, 1 Waiting, 2 Ready, 3 Done; a cancelled operation ALSO reads 3, because cancel() writes the same _DONE_MARKER execute() does). So a non-zero state means it is queued, finished, or killed -- one of those has a receipt and the other two are indistinguishable by state alone. Read the chain and the events instead of queueing a second copy."
  PAYLOAD="$SCHED"; LABEL="schedule"
  g="$(estimate "$(lc "$TIMELOCK")" "$SCHED")" || die "the node refused to estimate schedule(). With $need_role confirmed for the signer that means the timelock itself rejected the payload -- do not sign a transaction the chain has already said no to."
  GAS_SOURCE="eth_estimateGas x1.15"
else
  isop="$(rd "$TIMELOCK" 'isOperation(bytes32)(bool)' "$PROPOSAL_ID")"
  [ "$isop" = "true" ] || die "nothing is scheduled at this proposal id on chain $CHAIN. Run PHASE=schedule first and wait out the delay; executing an id that was never queued reverts with TimelockUnexpectedOperationState."
  ready="$(rd "$TIMELOCK" 'isOperationReady(bytes32)(bool)' "$PROPOSAL_ID")"
  eta="$(rd "$TIMELOCK" 'getTimestamp(bytes32)(uint256)' "$PROPOSAL_ID" | awk '{print $1}')"
  if [ "$ready" != "true" ]; then
    say "this proposal becomes executable at $(python3 -c "import datetime;print(datetime.datetime.fromtimestamp(${eta:-0},datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))") (chain time now $(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC_137" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16))'))"
    die "the delay has not elapsed (isOperationReady is $ready). Nothing is planned and nothing is signed -- which is correct: an execute broadcast early is a nonce spent on a revert, and the 48 h is the security property, not a queueing inconvenience."
  fi
  PAYLOAD="$EXEC"; LABEL="execute"
  # Estimated, because at this point the operation is ready and the node will price it honestly. The
  # measured cap is the fallback, not the default: it exists for the case where the estimate is refused
  # for a reason the guards above cannot see, and 21000 against a live timelock would strand the leg.
  if g="$(estimate "$(lc "$TIMELOCK")" "$PAYLOAD")"; then
    GAS_SOURCE="eth_estimateGas x1.15"
  else
    g="$(python3 "$PLAN_LIB" cap execute)"
    GAS_SOURCE="measured cap execute (the node refused the estimate)"
  fi
  say "ready to execute now; eta was $(python3 -c "import datetime;print(datetime.datetime.fromtimestamp(${eta:-0},datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
fi

python3 "$PLAN_LIB" add "$LABEL" "$START_NONCE" "$(lc "$TIMELOCK")" 0 "$PAYLOAD" "$g" "$MAXFEE" "$PRIORITY" \
  "$CHAIN" "$DEPLOYER" "$GAS_SOURCE" "$LABEL -> $ADMIN_SIG $ADMIN_ARGS on $ADMIN_TARGET via $TIMELOCK [$PROPOSAL_ID]"
say "PLAN  $LABEL nonce=$START_NONCE -> $TIMELOCK  gas=$g  [$GAS_SOURCE]"

# ---- serialise -----------------------------------------------------------------------------------
PLAN_START_NONCE="$START_NONCE" PLAN_CHAIN_ID="$CHAIN" PLAN_DEPLOYER="$DEPLOYER" PLAN_RPC="$RPC_137" \
PLAN_MAX_FEE="$MAXFEE" PLAN_PRIORITY_FEE="$PRIORITY" PLAN_PHASE="$PHASE" PLAN_STAMP="$STAMP" \
PLAN_PREDICTED_WLXON="$ADMIN_TARGET" PLAN_TIMELOCK="$TIMELOCK" PLAN_QUORUM="${QUORUM:-0}" \
PLAN_ADMIN_TARGET="$ADMIN_TARGET" PLAN_ADMIN_SIG="$ADMIN_SIG" PLAN_ADMIN_ARGS="$ADMIN_ARGS" \
PLAN_ATTESTOR="$ADMIN_ARGS" PLAN_PROPOSAL_ID="$PROPOSAL_ID" PLAN_ETA="${eta:-0}" \
PLAN_TIMELOCK_MIN_DELAY="$DELAY" PLAN_NATIVE_LXON="$(rd "$ADMIN_TARGET" 'nativeLXON()(address)')" \
PLAN_LEGACY="$(python3 -c "import json;print(json.load(open('deployments/wlxonsecure-chain-137.json')).get('legacyWlxon',''))" 2>/dev/null || true)" \
PLAN_FEE_SOURCE="$FEE_SOURCE" PLAN_CAPS_SOURCE="script/polygon137/lib/plan137.py CAPS (measured on the 137 fork)" \
PLAN_RESERVE=0 \
  python3 "$PLAN_LIB" finish | python3 -c "import sys,json;d=json.load(sys.stdin);print('  plan.json: %s (%d tx, nonce %d, %d gas)' % (d['plan'],d['transactions'],d['startNonce'],d['totalGas']))"

echo
if [ "$PHASE" = "schedule" ]; then
  echo "Next -- on the key host, then broadcast from anywhere that can reach $RPC_137:"
  echo "  PLAN_DIR=$PLAN_DIR KEYSTORE=<the 137 keystore> PASSWORD_FILE=<pw file> bash script/polygon137/SignWlxon137Plan.sh"
  echo "  PLAN_DIR=$PLAN_DIR SIGNED_DIR=$PLAN_DIR/signed WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/BroadcastWlxon137Signed.sh"
  echo
  echo "The execute leg is planned and signed when $PROPOSAL_ID is ready -- at least $(( DELAY / 3600 )) h after this mines,"
  echo "with the SAME ADMIN_SIG/ADMIN_ARGS/ATTESTOR so the id matches:"
  echo "  PHASE=execute PLAN_DIR=<new dir> DEPLOYER=$DEPLOYER ATTESTOR=$ADMIN_ARGS WLXON_I_ACCEPT_MAINNET_RISK=1 \\"
  echo "  bash script/polygon137/PlanAttestor137.sh"
else
  echo "This proposal is ready on chain now. Sign and broadcast:"
  echo "  PLAN_DIR=$PLAN_DIR KEYSTORE=<the 137 keystore> PASSWORD_FILE=<pw file> bash script/polygon137/SignWlxon137Plan.sh"
  echo "  PLAN_DIR=$PLAN_DIR SIGNED_DIR=$PLAN_DIR/signed WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/BroadcastWlxon137Signed.sh"
fi
