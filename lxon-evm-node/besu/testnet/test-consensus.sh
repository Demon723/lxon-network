#!/usr/bin/env bash
# M1 consensus gate. Four steps, each measured, nothing asserted by eye.
#   0. all four RPCs answer before anything is judged (readiness is not consensus)
#   1. all four nodes advance
#   2. killing one leaves the chain sealing   (n=4, f=1, quorum 3)
#   3. a fifth validator voted in seals
# Checks 1 and 2 assume the genesis roster of four validators. Once check 3 has run the roster
# is five, so check 2 needs five node containers up to stay true: quorum for n=5 is 4, and
# killing one of four running validators then halts the chain. See the runbook.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
FAIL=0

height() {
  curl -s "http://127.0.0.1:$1" -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
    | python3 -c 'import sys,json;print(int(json.load(sys.stdin)["result"],16))' 2>/dev/null || echo -1
}
rpc() { # rpc <port> <method> [params-json]
  local port="$1" method="$2" params="${3:-[]}"
  curl -s "http://127.0.0.1:$port" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
}
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; FAIL=1; }

# No mapfile here: macOS ships bash 3.2, where mapfile does not exist (bash 4.0+ only), and a
# missing command would leave the array empty so the gate aborts for the wrong reason.
GENESIS_CHAIN="$(python3 -c 'import json;g=json.load(open("725/genesis.json"))["config"]["chainId"];print(int(g,16) if isinstance(g,str) else g)')"
echo "chainId from genesis: $GENESIS_CHAIN (must be 725 -- this script must never run against production)"
[[ "$GENESIS_CHAIN" == "725" ]] || { echo "ABORT: genesis is not 725"; exit 1; }

# Readiness is a separate outcome from a consensus failure. Measured by Task 2's reviewer on a
# COLD store (nothing under 725/node-*): three of four RPCs still refuse to answer at T+95 s and
# node-1 reports peers=0; the 3/3/3/3 mesh only converges at T+145-170 s. A fixed `sleep 45` or
# `sleep 90` therefore reads height=-1 and prints "stalled" about a perfectly healthy chain -- a
# false consensus failure, which is the worst kind this script can make because the runbook would
# record it as a result. Poll instead, and abort as NOT READY rather than FAIL.
READY_BUDGET="${READY_BUDGET:-300}"
echo "--- 0. all four RPCs answering (budget ${READY_BUDGET}s, cold-store mesh needs ~170s) ---"
ready=0
for i in $(seq 1 $((READY_BUDGET / 10))); do
  n=0
  for P in 8645 8646 8647 8648; do [[ "$(height $P)" != "-1" ]] && n=$((n+1)); done
  echo "  attempt $i: $n/4 RPCs answering"
  if (( n == 4 )); then ready=1; break; fi
  sleep 10
done
if (( ! ready )); then
  echo "NOT READY: not all four RPCs answered within ${READY_BUDGET}s. This is a bring-up problem"
  echo "(cold store still syncing, stale BOOTNODE_1, wrong uid on a data dir), NOT a verdict on"
  echo "consensus. Check 'docker logs lxon-725-node-N | tail -30' before re-running."
  exit 2
fi

echo "--- 1. four nodes advancing ---"
declare -a H1 H2
for P in 8645 8646 8647 8648; do H1[$P]=$(height $P); done
sleep 15
for P in 8645 8646 8647 8648; do H2[$P]=$(height $P); done
for P in 8645 8646 8647 8648; do
  if (( ${H2[$P]} > ${H1[$P]} )); then ok "port $P ${H1[$P]} -> ${H2[$P]}"; else bad "port $P stalled at ${H2[$P]}"; fi
done

echo "--- 2. kill node-4, the chain must keep sealing ---"
docker stop lxon-725-node-4 >/dev/null
sleep 3
declare -a K1 K2
for P in 8645 8646 8647; do K1[$P]=$(height $P); done
sleep 20
for P in 8645 8646 8647; do K2[$P]=$(height $P); done
for P in 8645 8646 8647; do
  if (( ${K2[$P]} > ${K1[$P]} )); then ok "survivor $P advanced ${K1[$P]} -> ${K2[$P]} with node-4 down"; else bad "chain halted when node-4 stopped (quorum broken?)"; fi
done
docker start lxon-725-node-4 >/dev/null; sleep 15

echo "--- 3. vote validator 5 in (on every live validator, not just node-1) ---"
SPARE=$(sed -n '5p' validator-addresses.txt)
[[ -n "$SPARE" ]] || { bad "no spare validator address"; }
echo "spare validator: $SPARE"
BEFORE=$(rpc 8645 qbft_getValidatorsByBlockNumber '["latest"]')
if grep -qi "${SPARE#0x}" <<<"$BEFORE"; then
  echo "spare is already a validator; re-running this gate does not re-test the transition"
fi
# Check 2 restarted node-4 a few seconds ago and its RPC takes ~20-40 s to answer. Wait for it,
# because the roster change only applies once a quorum of validators holds the vote: measured on
# this chain, three of four validators voting applied it at height 371 within two blocks, while
# one validator voting (node-1 alone) never applied it at all through six epoch boundaries.
# Skipping this wait makes the gate depend on how fast the node it just killed comes back.
for P in 8645 8646 8647 8648; do
  for t in $(seq 1 12); do
    (( $(height $P) >= 0 )) && break
    sleep 5
  done
done
# Measured on Besu 26.10 QBFT: a vote cast on ONE node never applies. Voting the spare in
# from node-1 only left the set at 4 through heights 60, 90, 120, 150 and 162, including two
# checkpoints node-1 proposed itself -- the votes field of those blocks stayed empty. Casting
# the same vote on every live validator applied it at height 234, two blocks later, and the
# roster in the block extraData went from 4 to 5 with the seal list from 3 to 4. So the vote
# goes to every RPC port that is up; a port that is down just returns nothing.
VOTES=""
for P in 8645 8646 8647 8648 8649; do
  VOTES="$VOTES ${P}=$(rpc $P qbft_proposeValidatorVote "[\"$SPARE\",true]")"
done
echo "vote responses:$VOTES"
# The wait is a ceiling, not a prediction. Measured above: once a quorum of validators holds the
# vote it applies within about two blocks (~6-10 s), not at the next epoch boundary -- 234 is not
# a multiple of epochlength 30. So 30 x 10 s is only here to catch the case where the votes did
# not reach a quorum at all.
echo "waiting up to 300 s for the transition (a quorum vote applies in ~2 blocks, not at an epoch)…"
JOINED=0
for i in $(seq 1 30); do
  sleep 10
  AFTER=$(rpc 8645 qbft_getValidatorsByBlockNumber '["latest"]')
  if grep -qi "${SPARE#0x}" <<<"$AFTER"; then JOINED=1; H=$(height 8645); break; fi
done
if (( JOINED )); then ok "node 5 is a validator (observed at height $H after $((i*10)) s)"
else bad "node 5 never appeared in the validator set: before=$BEFORE after=${AFTER:-none}"; fi

echo "--- result ---"
[[ $FAIL -eq 0 ]] && echo "CONSENSUS GATE OK" || echo "CONSENSUS GATE FAILED"
exit $FAIL
