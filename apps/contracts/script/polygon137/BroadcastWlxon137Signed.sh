#!/usr/bin/env bash
# Broadcast a signed Polygon-137 wLXONSecure/migration plan. Nothing here touches a key: the input is a
# directory of signed transactions, which is a public artefact -- a signature proves who signed, it does
# not reveal them. That is what makes the split safe: the machine holding the 137 deployer key never has
# to be reachable from the launch, and the launch machine never has to be trusted with anything secret.
#
#   PLAN_DIR=/tmp/wlxon137-deploy SIGNED_DIR=/tmp/wlxon137-deploy/signed \
#   bash script/polygon137/BroadcastWlxon137Signed.sh
#
# Pass 1 verifies every signature against the plan before publishing any of it: signer (recovered from
# the signature itself), nonce, chain id, destination, value, BOTH EIP-1559 fee fields, gas limit,
# calldata and that it is a type-2 transaction. A signed transaction is authorisation to move money, so
# the broadcaster checks the authorisation instead of assuming the plan and the batch came from the same
# run.
#
# Pass 2 publishes in nonce order and waits for each receipt, because the creates decide facts the rest
# of the batch depends on: setNewToken names the wLXONSecure address the plan *predicted*. If the chain
# puts that contract anywhere else, continuing would wire a migration to a token that does not exist and
# then pay a reserve into it.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="script/polygon137/lib/offline_plan1559.py"
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

PLAN_DIR="${PLAN_DIR:?usage: PLAN_DIR=<dir with plan.json> SIGNED_DIR=<dir of signed raw txs> bash script/polygon137/BroadcastWlxon137Signed.sh}"
SIGNED_DIR="${SIGNED_DIR:?usage: SIGNED_DIR=<directory SignWlxon137Plan.sh wrote>}"
export PLAN_DIR
[ -f "$PLAN_DIR/plan.json" ] || { echo "FATAL: no $PLAN_DIR/plan.json" >&2; exit 1; }
ls "$SIGNED_DIR"/*.raw.hex >/dev/null 2>&1 || { echo "FATAL: no .raw.hex files in $SIGNED_DIR" >&2; exit 1; }
# The same refusal as the signer: a broadcaster that can sign has stopped being the half that sees no secret.
[ -z "${PRIVATE_KEY:-}" ] || { echo "FATAL: this script publishes signatures; it needs no key. PRIVATE_KEY= is refused." >&2; exit 1; }

RPC="$(python3 "$LIB" field rpc)"
CHAIN="$(python3 "$LIB" field chainId)"
FROM="$(python3 "$LIB" field from)"
START="$(python3 "$LIB" field startNonce)"
NTX="$(python3 "$LIB" field txCount)"
PHASE="$(python3 "$LIB" field phase)"
PWX="$(python3 "$LIB" field predictedWlxon)"
PTL="$(python3 "$LIB" field predictedTimelock)"
TLMODE="$(python3 "$LIB" field timelockMode)"
TLDelay="$(python3 "$LIB" field timelockMinDelay)"
PM="$(python3 "$LIB" field predictedMigration)"
LEGACY="$(python3 "$LIB" field legacyWlxon)"
TIMELOCK="$(python3 "$LIB" field timelock)"
QUORUM="$(python3 "$LIB" field quorum)"
NATIVE="$(python3 "$LIB" field nativeLXON)"
RESERVE="$(python3 "$LIB" field reserveWei)"
WINDOW="$(python3 "$LIB" field opensMigrationWindow)"
[ -n "${RPC_OVERRIDE:-}" ] && RPC="$RPC_OVERRIDE"
echo "  plan: chain=$CHAIN phase=${PHASE:-?} from=$FROM start nonce=$START rpc=$RPC"
[ -z "$PTL" ] || echo "        predicted timelock=$PTL  (mode ${TLMODE:-?}, minDelay ${TLDelay:-n/a} s)"
[ -z "$PWX" ] || echo "        predicted wLXONSecure=$PWX"
[ -z "$PM" ] || echo "        predicted migration=$PM"

# which predicted address a create label must land on
expect_created() { case "$1" in TIMELOCK) printf '%s' "$PTL";; WLXON) printf '%s' "$PWX";; MIGRATION) printf '%s' "$PM";; *) echo "";; esac; }

TXS="$(python3 "$LIB" txs)"
n=0
while IFS="$(printf '\t')" read -r label nonce to value data gas maxfee priority; do
  [ -n "$label" ] || continue
  idx="$(printf '%02d' "$n")"
  f="$(ls "$SIGNED_DIR/$idx-"*.raw.hex 2>/dev/null | head -1 || true)"
  [ -n "$f" ] || { echo "BAD  $idx-$label: no signed transaction with this index -- the batch is incomplete"; exit 1; }
  # The filename must name the same step the plan puts at this index; otherwise a renamed file swaps one
  # transaction for another while every field still checks out.
  case "$(basename "$f")" in
    "$idx-$label."*) ;;
    *) echo "BAD  $idx-$label: $(basename "$f") is labelled for a different step than the plan puts at nonce $nonce"; exit 1 ;;
  esac
  chk="$(python3 "$LIB" verify "$f" "$nonce" "$to" "$value" "$data" "$gas" "$maxfee" "$priority" "$CHAIN" "$FROM")" \
    || { echo "BAD  $idx-$label: $chk"; exit 1; }
  where="-> $to"
  [ "$to" = "0x" ] && where="CREATE"
  printf '  OK %s-%s  nonce=%s  %s  %s hex calldata, signed by %s\n' "$idx" "$label" "$nonce" "$where" \
    "$(printf '%s' "$data" | wc -c | tr -d ' ')" "$FROM"
  n=$((n + 1))
done <<EOF
$TXS
EOF
echo "  all $n signatures decode as the plan says, nonces $(printf '%s' "$TXS" | head -1 | cut -f2)..$(printf '%s' "$TXS" | tail -1 | cut -f2)"

# A plan is single use. If this key is already past the plan's first nonce the signatures are dead.
lower_from="$(printf '%s' "$FROM" | tr 'A-Z' 'a-z')"
got_chain="$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$got_chain" ] || { echo "FATAL: $RPC did not answer eth_chainId" >&2; exit 1; }
[ "$(python3 -c "print(int('$got_chain',16))")" = "$CHAIN" ] \
  || { echo "FATAL: $RPC answers chain $got_chain and this plan is for $CHAIN -- nothing here would land." >&2; exit 1; }
latest="$(cast rpc eth_getTransactionCount "$lower_from" latest --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$latest" ] || { echo "FATAL: $RPC did not answer eth_getTransactionCount" >&2; exit 1; }
now="$(python3 -c "print(int('$latest',16))")"
if [ "$now" != "$START" ]; then
  echo "FATAL: $lower_from is at nonce $now and this plan starts at $START."
  echo "       If these transactions are already on chain, read the contracts at ${PWX:-the predicted} /"
  echo "       ${PM:-the predicted} addresses and stop. If something else moved this key, both predicted"
  echo "       addresses are wrong and the batch must be re-planned and re-signed -- not nudged along by"
  echo "       editing nonces."
  exit 1
fi

if [ "$WINDOW" = "True" ]; then
  echo "  THIS BATCH OPENS THE MIGRATION WINDOW at nonce $((START + NTX - 1)). Users can migrate from that"
  echo "  block onward, 1:1 against the reserve this contract holds at that moment."
else
  echo "  This plan does not open the window: ${PHASE:-deploy} lands the contracts wired and closed, and"
  echo "  startMigration() is a later, separate, deliberate batch."
fi
[ "${FORCE:-0}" = "1" ] || { printf 'broadcast %s transactions to %s? [y/N] ' "$NTX" "$RPC"; read -r ans; case "$ans" in y|Y) ;; *) echo "aborted by operator"; exit 1;; esac; }

REC="$PLAN_DIR/launch-record.json"
REC_LINES=""
mkdir -p "$PLAN_DIR"
n_done=0
CREATED_TIMELOCK=""
CREATED_WLXON=""
CREATED_MIGRATION=""
while IFS="$(printf '\t')" read -r label nonce to value data gas maxfee priority; do
  [ -n "$label" ] || continue
  idx="$(printf '%02d' "$n_done")"
  f="$(ls "$SIGNED_DIR/$idx-"*.raw.hex | head -1)"
  raw="0x$(tr -d '[:space:]' < "$f")"
  h="$(python3 "$LIB" hash "$f")"
  echo "==> $idx-$label  nonce=$nonce  tx=$h"
  sent="$(cast rpc eth_sendRawTransaction "$raw" --rpc-url "$RPC" 2>&1 || true)"
  case "$sent" in
    *"$h"*) ;;
    *) echo "FATAL: the node did not accept $label; it answered: $(printf '%s' "$sent" | head -c 300)"
       echo "        Stopped before publishing anything after it. Read the chain before signing another plan." >&2
       echo "        Published so far: $n_done of $NTX. Record: $REC" >&2; exit 1 ;;
  esac
  # Poll by the hash recovered from the signature, never by grepping a 64-hex field out of a text
  # receipt: a receipt prints the block hash before the transaction hash, and parsing the wrong one is
  # how a completed launch looks like it is hanging.
  r=""
  for i in $(seq 1 90); do
    r="$(cast rpc eth_getTransactionReceipt "$h" --rpc-url "$RPC" 2>/dev/null || true)"
    case "$r" in *'"status"'*) break ;; esac
    sleep 2
  done
  status="$(printf '%s' "$r" | python3 "$LIB" receipt status)"
  [ "$status" = "0x1" ] || { echo "FATAL: $label landed with status ${status:-not mined}. Everything after it is un-broadcast on purpose."; exit 1; }
  block="$(printf '%s' "$r" | python3 "$LIB" receipt blockNumber)"
  created=""
  if [ "$to" = "0x" ]; then
    created="$(printf '%s' "$r" | python3 "$LIB" receipt contractAddress | tr 'A-Z' 'a-z')"
    wantep="$(expect_created "$label" | tr 'A-Z' 'a-z')"
    if [ -n "$wantep" ] && [ "$created" != "$wantep" ]; then
      echo "FATAL: $label was created at $created but the plan (and every later transaction) names $wantep."
      echo "       STOP: the batch no longer matches the chain. Do not hand-edit the rest and carry on." >&2
      exit 1
    fi
    [ "$label" = "TIMELOCK" ] && CREATED_TIMELOCK="$created"
    [ "$label" = "WLXON" ] && CREATED_WLXON="$created"
    [ "$label" = "MIGRATION" ] && CREATED_MIGRATION="$created"
    echo "    created at $created -- matches the plan"
  fi
  echo "    mined in block $(python3 -c "print(int('${block:-0x0}',16))")"
  # "index" is %d, not %s: the file index is printed as 00/01 for sort order, and `{"index":00}` is not
  # JSON -- a leading zero is illegal, so the record step died on its own output after every transaction
  # had already mined. A launch record that fails to write is the worst possible late failure.
  REC_LINES="$REC_LINES$(printf '{"index":%d,"label":"%s","nonce":%s,"txHash":"%s","block":%s,"contractAddress":"%s"},\n' \
    "$idx" "$label" "$nonce" "$h" "$(python3 -c "print(int('${block:-0x0}',16))")" "$created")"
  n_done=$((n_done + 1))
done <<EOF
$TXS
EOF

# ---- read back what the chain actually says -----------------------------------------------------
# Every expectation below comes from plan.json and is answered by the node, not by this script's own
# variables. That is the difference between a launch record and a receipt printer: a payload mis-encoded
# by the planner still mines with status 0x1, and only the stored value tells you it said the wrong thing.
WLXON="${PWX:-$CREATED_WLXON}"
MIGRATION="${PM:-$CREATED_MIGRATION}"
TIMELOCK="${TIMELOCK:-$CREATED_TIMELOCK}"
ADMIN_ROLE_ID="$(cast keccak 'ADMIN_ROLE' 2>/dev/null | head -1)"
echo
echo "Read-back (chain $CHAIN via $RPC):"
rd() { local addr="$1" sig="$2"; shift 2; cast call "$addr" "$sig" "$@" --rpc-url "$RPC" 2>/dev/null | head -1; }
if [ "$PHASE" = "deploy" ] && [ -n "$WLXON" ] && [ -n "$MIGRATION" ]; then
  if [ "$TLMODE" = "create" ] && [ -n "$TIMELOCK" ]; then
    # The custody claim this batch exists to make, asked of the chain rather than asserted here: the
    # timelock is at the predicted address, it really holds a delay, and the deployer cannot configure
    # wLXONSecure directly any more.
    printf '  timelock           = %s   (created by this batch at nonce %s)\n' "$TIMELOCK" "$START"
    printf '  timelock delay     = %s   (plan says %s)\n' "$(rd "$TIMELOCK" 'getMinDelay()(uint256)')" "${TLDelay:-?}"
    printf '  deployer PROPOSER?  = %s   (must be true -- without it nothing can ever be queued)\n' "$(rd "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$(cast keccak 'PROPOSER_ROLE')" "$FROM")"
    printf '  deployer ADMIN_ROLE on wLXON = %s   (must be false: the signer cannot self-configure)\n' "$(rd "$WLXON" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE_ID" "$FROM")"
  fi
  printf '  wLXONSecure        = %s\n' "$WLXON"
  printf '  nativeLXON         = %s   (plan says %s)\n' "$(rd "$WLXON" 'nativeLXON()(address)')" "${NATIVE:-?}"
  printf '  sourceChainId      = %s   (plan says 724)\n' "$(rd "$WLXON" 'sourceChainId()(uint256)')"
  printf '  targetChainId      = %s   (plan says %s)\n' "$(rd "$WLXON" "targetChainId()(uint256)")" "$CHAIN"
  printf '  quorum             = %s   (plan says %s)\n' "$(rd "$WLXON" 'quorum()(uint256)')" "${QUORUM:-?}"
  printf '  ADMIN_ROLE held by = %s   (plan says %s)\n' "$(rd "$WLXON" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE_ID" "$(lc "${TIMELOCK:-0x0000000000000000000000000000000000000000}")")" "${TIMELOCK:-?}"
  printf '  checkBacking       = %s   (true at supply 0; it must stay true)\n' "$(rd "$WLXON" 'checkBacking()(bool)')"
  printf '  migration          = %s\n' "$MIGRATION"
  printf '  oldWLXON           = %s   (plan says %s)\n' "$(rd "$MIGRATION" 'oldWLXON()(address)')" "${LEGACY:-?}"
  printf '  newWLXON           = %s   (must equal wLXONSecure above)\n' "$(rd "$MIGRATION" 'newWLXON()(address)')"
  printf '  migrationActive    = %s   (this plan %s open the window)\n' "$(rd "$MIGRATION" 'migrationActive()(bool)')" "$([ "$WINDOW" = "True" ] && echo 'DID' || echo 'did NOT')"
  printf '  reserveBalance     = %s   (funded by the PHASE=fund batch)\n' "$(rd "$MIGRATION" 'reserveBalance()(uint256)')"
fi
if [ "$PHASE" = "fund" ]; then
  printf '  reserveBalance     = %s   (plan moved %s)\n' "$(rd "$MIGRATION" 'reserveBalance()(uint256)')" "${RESERVE:-?}"
  printf '  migrationActive    = %s   (plan opened the window: %s)\n' "$(rd "$MIGRATION" 'migrationActive()(bool)')" "$WINDOW"
  printf '  window ends        = %s\n' "$(rd "$MIGRATION" 'migrationEndTime()(uint256)')"
fi

# The admin ceremony (PHASE=schedule|execute) is read back differently, because what it bought is not a
# value in a storage slot but a STATE in the timelock: a schedule that mined with status 0x1 and queued
# nothing -- a wrong id, a wrong target -- is indistinguishable from a good one until someone asks for the
# proposal. So ask, by the id the plan carries, and print the eta the chain computed rather than the delay
# the operator hoped for.
ATTESTOR_PID="$(python3 "$LIB" field proposalId)"
ATT_ADMIN="$(python3 "$LIB" field attestor)"
ADM_TARGET="$(python3 "$LIB" field adminTarget)"
if { [ "$PHASE" = "schedule" ] || [ "$PHASE" = "execute" ]; } && [ -n "$ATTESTOR_PID" ] && [ -n "$TIMELOCK" ]; then
  AT_ID="$(rd "${ADM_TARGET:-$PWX}" 'ATTESTOR_ROLE()(bytes32)')"
  printf '  proposal           = %s\n' "$ATTESTOR_PID"
  # OZ 5.6.1's enum is {Unset, Waiting, Ready, Done} -- four values, no Cancelled. cancel() writes the same
  # DONE_MARKER that execute() does, so state 3 means "finished" and getTimestamp 1 means "Done OR
  # Cancelled"; the only thing that tells them apart is whether the role actually flipped. Printing a
  # invented "4 Cancelled" here would have told the next reader the opposite of the truth.
  printf '  state on chain     = %s   (OZ OperationState: 0 Unset, 1 Waiting, 2 Ready, 3 Done -- Cancelled also reads 3)\n' "$(rd "$TIMELOCK" 'getOperationState(bytes32)(uint8)' "$ATTESTOR_PID" | awk '{print $1}')"
  printf '  isOperationReady   = %s\n' "$(rd "$TIMELOCK" 'isOperationReady(bytes32)(bool)' "$ATTESTOR_PID")"
  # getTimestamp returns 1, not the old eta, once an operation is finished -- OZ writes _DONE_MARKER, which
  # execute() and cancel() share. So 1 proves "this proposal is closed", not "it succeeded": the role flip
  # below is the evidence, and if the state reads 3 while the role did not change, the proposal was cancelled.
  printf '  eta                = %s   (1 = closed: executed or cancelled)   chain time now %s\n' \
    "$(rd "$TIMELOCK" 'getTimestamp(bytes32)(uint256)' "$ATTESTOR_PID" | awk '{print $1}')" "$(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC" 2>/dev/null | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16))')"
  if [ -n "$ATT_ADMIN" ]; then
    printf '  ATTESTOR_ROLE held by %s = %s\n' "$ATT_ADMIN" "$(rd "${ADM_TARGET:-$PWX}" "hasRole(bytes32,address)(bool)" "$AT_ID" "$(lc "$ATT_ADMIN")")"
  fi
  printf '  quorum             = %s   (one attestor with quorum 2 mints nothing; totalSupply %s)\n' "$(rd "${ADM_TARGET:-$PWX}" 'quorum()(uint256)' | awk '{print $1}')" "$(rd "${ADM_TARGET:-$PWX}" 'totalSupply()(uint256)' | awk '{print $1}')"
  printf '  direct admin call by signer = %s   (must stay false: custody is still the timelock'"'"'s)\n' "$(rd "${ADM_TARGET:-$PWX}" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE_ID" "$FROM")"
fi

python3 - "$REC" "$CHAIN" "$PHASE" "$n_done" "$START" "$RPC" "$FROM" "${WLXON:-}" "${MIGRATION:-}" "$REC_LINES" "${ATTESTOR_PID:-}" "${ATT_ADMIN:-}" "${TIMELOCK:-}" <<'PY'
import json, sys, datetime
rec, chain, phase, n, start, rpc, frm, wlxon, mig, lines, pid, attestor, timelock = sys.argv[1:14]
steps = json.loads("[%s]" % lines.rstrip().rstrip(","))
out = {"kind": "lxon-wlxonsecure-137-launch-record", "chainId": int(chain), "phase": phase,
       "broadcastAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "rpc": rpc, "signer": frm, "startNonce": int(start), "transactions": int(n),
       "wlxonSecure": wlxon or None, "migration": mig or None, "steps": steps}
if pid:
    # An admin ceremony's record is the proposal id plus which key it moved. Without these two strings a
    # later reader cannot tell what was queued, only that a transaction mined.
    out["proposalId"] = pid
    out["attestor"] = attestor or None
    out["timelock"] = timelock or None
json.dump(out, open(rec, "w"), indent=1)
print("  record written: %s" % rec)
PY

echo
echo "All $n_done transactions mined. If this was the deploy phase, the two addresses above are the inputs"
echo "the fund phase names -- copy them out of THIS output, do not retype: WLXON_MIGRATION_NEW and"
echo "WLXON_MIGRATION for PlanWlxon137.sh PHASE=fund come from the chain, not from the plan."
echo "wLXONSecure has no attestors registered and no window open yet; both are separate, deliberate acts."
