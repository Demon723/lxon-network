#!/usr/bin/env bash
# Six attacks against the deployed attested bridge, run as real transactions, plus the two claims
# that must succeed afterwards. A PASS means the chain REJECTED the attack, which is the outcome we
# want; the last two lines are the positive control that shows the rejections were not accidents.
#
# Inputs come from build-attack-inputs.py, which derives them from live chain state. Not idempotent
# by design: the fresh transfers it locks are spent once, so a second run says ALREADY EXERCISED
# rather than reporting a false pass. Re-run build-attack-inputs.py first for another sweep.
#
# Attack 4 is deliberately NOT the attack the plan described. Raising `amount` in a request whose
# signatures were collected over the ORIGINAL claimId reverts `signer not a validator`, not
# `total mismatch` -- computeClaimId covers every field, so inflating one invalidates the attestation
# before the ledger arithmetic is ever reached. That is a stronger property than the plan assumed, so
# it is asserted here instead of the weaker one. The gapless-total guard is reachable only by a
# bundle a quorum really signed, which is exactly what attack 6 (claim the second transfer before the
# first) produces.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
RPC725=http://127.0.0.1:8645
RPC726=http://127.0.0.1:8665
TESTNET_PK="$(cat keys/deployer.hex)"
BRIDGE725=$(python3 -c "import json;print(json.load(open('/tmp/env.json'))['BRIDGE725'])")
BRIDGE726=$(python3 -c "import json;print(json.load(open('/tmp/env.json'))['BRIDGE726'])")
FT="claimTransfer((uint256,uint256,uint256,uint256,address,uint256,address,address,uint256),bytes[])"
FAIL=0

status_of() { # status_of <id> -- 0 means never claimed
  cast call "$BRIDGE726" "claims(bytes32)((uint8,uint256,address,uint256))" "$1" --rpc-url "$RPC726" \
    | sed -n 's/^(\([0-9]*\),.*/\1/p'
}

attempt() { # attempt <label> <expected-revert> <bridge> <rpc> <req> <sigs>
  local label="$1" expect="$2" bridge="$3" rpc="$4" req="$5" sigs="$6" out status
  out=$(cast send "$bridge" "$FT" "$req" "$sigs" --rpc-url "$rpc" --private-key "$TESTNET_PK" --json 2>&1 || true)
  # Status comes from the receipt JSON, not from pattern-matching prose: a reverted transaction and a
  # broadcast failure look similar in text but differ in this field.
  status=$(python3 -c "
import json,sys
try: print(json.loads(sys.stdin.read()).get('status'))
except Exception: print('unparsed')
" <<<"$out")
  if [[ "$status" == "0x1" ]]; then
    echo "FAIL $label -> the attack SUCCEEDED (status 0x1)"; FAIL=1
  elif grep -qi "$expect" <<<"$out"; then
    echo "PASS $label -> rejected with: $expect"
  else
    echo "FAIL $label -> reverted, but not with the expected reason (status=$status)"
    grep -io 'revert[^\"]*\|"[^"]*"' <<<"$out" | grep -i -m1 '.' | sed 's/^/      actual: /'
    FAIL=1
  fi
}

expect_success() { # expect_success <label> <bridge> <rpc> <req> <sigs>
  local label="$1" bridge="$2" rpc="$3" req="$4" sigs="$5" out status
  out=$(cast send "$bridge" "$FT" "$req" "$sigs" --rpc-url "$rpc" --private-key "$TESTNET_PK" --json 2>&1 || true)
  status=$(python3 -c "
import json,sys
try: print(json.loads(sys.stdin.read()).get('status'))
except Exception: print('unparsed')
" <<<"$out")
  if [[ "$status" == "0x1" ]]; then echo "PASS $label -> credited (status 0x1)"
  else echo "FAIL $label -> the legitimate claim did not go through (status=$status)"; FAIL=1; fi
}

L2_ID=$(cat /tmp/attack_l2_id.txt); L3_ID=$(cat /tmp/attack_l3_id.txt); L4_ID=$(cat /tmp/attack_l4_id.txt)
for pair in "L2 $L2_ID" "L3 $L3_ID" "L4 $L4_ID"; do
  set -- $pair
  if [[ "$(status_of "$2")" != "0" ]]; then
    echo "ALREADY EXERCISED: $1 ($2) is not in state None, so this sweep cannot prove anything."
    echo "Re-run ./build-attack-inputs.py to lock fresh transfers, then run this again."
    exit 3
  fi
done

REQ="$(cat /tmp/attack_req.txt)"
SIGS="$(cat /tmp/attack_sigs.txt)"
SIGS2="$(cat /tmp/attack_sigs_two.txt)"
REQ_OVER="$(cat /tmp/attack_req_over.txt)"
L2_REQ="$(cat /tmp/attack_l2_req.txt)";  L2_SIGS="$(cat /tmp/attack_l2_sigs.txt)"
L3_REQ="$(cat /tmp/attack_l3_req.txt)";  L3_SIGS="$(cat /tmp/attack_l3_sigs.txt)"
L4_REQ="$(cat /tmp/attack_l4_req.txt)";  L4_SIGS_REV="$(cat /tmp/attack_l4_sigs_rev.txt)"

echo "--- 1. exact replay of a completed claim ---"
attempt "double claim" "already claimed" "$BRIDGE726" "$RPC726" "$REQ" "$SIGS"

echo "--- 2. the 726 bundle replayed against 725's bridge ---"
attempt "cross-chain replay" "wrong destination chain" "$BRIDGE725" "$RPC725" "$REQ" "$SIGS"

echo "--- 3. two signatures where the threshold is three ---"
attempt "below quorum" "below quorum" "$BRIDGE726" "$RPC726" "$REQ" "$SIGS2"

echo "--- 4. amount inflated under the original signatures ---"
attempt "over-credit" "signer not a validator" "$BRIDGE726" "$RPC726" "$REQ_OVER" "$SIGS"

echo "--- 5. bundle presented out of ascending order (unclaimed request) ---"
attempt "unsorted bundle" "not ascending" "$BRIDGE726" "$RPC726" "$L4_REQ" "$L4_SIGS_REV"

echo "--- 6. the second transfer claimed before the first (gapless total) ---"
attempt "reorder / skip value" "total mismatch" "$BRIDGE726" "$RPC726" "$L3_REQ" "$L3_SIGS"

echo "--- positive control: the same two transfers claimed in order ---"
expect_success "claim L2 in order" "$BRIDGE726" "$RPC726" "$L2_REQ" "$L2_SIGS"
expect_success "claim L3 in order" "$BRIDGE726" "$RPC726" "$L3_REQ" "$L3_SIGS"

echo "--- books ---"
SENT725=$(cast call "$BRIDGE725" "totalSentFor(uint256)(uint256)" 726 --rpc-url "$RPC725")
RECV726=$(cast call "$BRIDGE726" "totalReceivedFrom(uint256)(uint256)" 725 --rpc-url "$RPC726")
SENT726=$(cast call "$BRIDGE726" "totalSentFor(uint256)(uint256)" 725 --rpc-url "$RPC726")
RECV725=$(cast call "$BRIDGE725" "totalReceivedFrom(uint256)(uint256)" 726 --rpc-url "$RPC725")
X726=$(python3 -c "import json;print(json.load(open('/tmp/env.json'))['XLXON726'])")
SUP726=$(cast call "$X726" "totalSupply()(uint256)" --rpc-url "$RPC726")
INFLIGHT=$(python3 -c "
v=open('/tmp/attack_l4_req.txt').read().strip().strip('()').split(',')
print(int(v[5]))")   # the amount of the transfer attack 5 deliberately left unclaimed
echo "725 totalSentFor(726)      $SENT725"
echo "726 totalReceivedFrom(725) $RECV726"
echo "726 totalSentFor(725)      $SENT726"
echo "725 totalReceivedFrom(726) $RECV725"
echo "xLXON supply on 726        $SUP726"
echo "in flight (L4, unclaimed)  $INFLIGHT"
# Two invariants that hold no matter how many transfers are still in flight, plus a ledger check that
# a REJECTED attack must not have written anything. sent >= received is the gapless rule seen from the
# destination: 726 can never credit more than 725 has attested. supply == received - returned is the
# mint rule: representations only exist behind a credit that has not been returned yet.
python3 - "$SENT725" "$RECV726" "$RECV725" "$SUP726" "$INFLIGHT" <<'PY'
import sys
sent, recv, back, supply, inflight = (int(x.split()[0]) for x in sys.argv[1:6])
ok = True
if recv > sent:
    print(f"FAIL 726 credited {recv} but 725 only attested {sent}"); ok = False
else:
    print(f"PASS nothing credited beyond the source's attestation (in flight: {sent - recv})")
if sent - recv < inflight:
    print(f"FAIL the unclaimed transfer attack 5 relies on ({inflight}) is not inside the in-flight gap"); ok = False
if supply != recv - back:
    print(f"FAIL xLXON supply {supply} != credited {recv} minus returned {back} = {recv - back}"); ok = False
else:
    print(f"PASS xLXON supply equals credited minus returned ({supply})")
sys.exit(0 if ok else 1)
PY
[[ $? -eq 0 ]] || FAIL=1

echo "--- rejected attacks left no ledger entry ---"
OVER_ID=$(cast call "$BRIDGE726" "computeClaimId((uint256,uint256,uint256,uint256,address,uint256,address,address,uint256))(bytes32)" "$REQ_OVER" --rpc-url "$RPC726")
for pair in "over-credit $OVER_ID" "unsorted-bundle $L4_ID"; do
  set -- $pair
  ST=$(status_of "$2")
  if [[ "$ST" == "0" ]]; then echo "PASS $1 ($2) is still state None -- the rejection wrote nothing"
  else echo "FAIL $1 claimed the ledger despite reverting (status $ST)"; FAIL=1; fi
done

echo "--- result ---"
[[ $FAIL -eq 0 ]] && echo "ALL ATTACKS REJECTED" || echo "SOME ATTACKS SUCCEEDED"
exit $FAIL
