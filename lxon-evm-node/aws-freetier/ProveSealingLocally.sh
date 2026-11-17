#!/usr/bin/env bash
# Prove the validator key actually SEALS this genesis, locally, before spending AWS credits.
#
# ProveGenesisLocally.sh proves block 0. It cannot prove the chain advances, because block 0
# needs no sealer. This closes that gap: it runs the real entrypoint, the real mount layout and
# the production validator key, then requires the head to move and block 1's miner to be the
# genesis validator. Only the holder of that key can produce such a block.
#
# ISOLATION -- this uses the production sealer key, so it is deliberately unable to reach
# anything: --discovery-enabled=false, --max-peers=0, loopback-only RPC, an ephemeral port, and
# the chain data is destroyed on exit. The real chain-724 network no longer exists (its host was
# terminated), and nothing here can publish a block to it. The key is never printed, never copied
# out of its existing 0600 file, and never passed on a command line.
#
#   ./ProveSealingLocally.sh
#   SEALER_KEY=/path/to/key ./ProveSealingLocally.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="$(dirname "$SCRIPT_DIR")"
GENESIS="${GENESIS:-${GENESIS_FILE:-${SCRIPT_DIR}/genesis/genesis.qbft.json}}"
SEALER_KEY="${SEALER_KEY:-${NODE_DIR}/besu/privatekey.txt}"
ENTRYPOINT="${ENTRYPOINT:-${NODE_DIR}/besu/entrypoint-besu.sh}"
BESU_IMAGE="${BESU_IMAGE:-hyperledger/besu:26.10.0}"
EXPECTED_VALIDATOR="${EXPECTED_VALIDATOR:-0xfae699d2848957c7c3be67d8c90f0e456419cada}"
EXPECTED_BLOCK0="${EXPECTED_BLOCK0:-0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588}"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-20}"   # blockperiodseconds is 5, so this should show ~3-4 blocks
CNAME="lxon-seal-proof"
WORK="${WORK:-$HOME/.lxon/runs/seal-proof}"    # never /tmp: a startup sweep deletes /tmp/lxon-*

fail() { echo "  FAIL $*" >&2; }
cleanup() {
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
  [ "${KEEP_WORK:-0}" = 1 ] || rm -rf "$WORK"
}
die() { fail "$*"; cleanup; exit 1; }
trap cleanup EXIT

echo "==> ProveSealingLocally"
echo "    genesis    : $GENESIS"
echo "    sealer key : $SEALER_KEY   (contents never printed)"
echo "    entrypoint : $ENTRYPOINT"
echo "    validator  : $EXPECTED_VALIDATOR"

[ -f "$GENESIS" ]    || die "genesis not found: $GENESIS"
[ -f "$ENTRYPOINT" ] || die "entrypoint not found: $ENTRYPOINT"
[ -s "$SEALER_KEY" ] || die "sealer key missing or EMPTY: $SEALER_KEY (Besu aborts on an empty key file)"

# A read-only bind mount of a single file needs the source to exist; compose does the same.
# Exercise the REAL entrypoint, exactly as compose does (--entrypoint /bin/sh + the script as
# its argument). That entrypoint execs besu with its OWN hardcoded flags and ignores anything
# passed here, so isolation flags cannot be injected -- they have to be MEASURED afterwards
# (net_peerCount below). The genesis carries no bootnodes, discovery has no seeds and the old
# chain-724 network no longer exists, so the peer count must come back 0x0; if it does not, this
# test fails rather than proceeding.
rm -rf "$WORK"; mkdir -p "$WORK/besu-data"
chmod 0777 "$WORK/besu-data"     # stands in for what the besu-perms service does as uid 0

docker run -d --name "$CNAME" \
  --user 1000:1000 \
  -v "$GENESIS:/etc/besu/genesis.json:ro" \
  -v "$ENTRYPOINT:/scripts/entrypoint-besu.sh:ro" \
  -v "$SEALER_KEY:/key/key.priv:ro" \
  -v "$WORK/besu-data:/var/lib/besu" \
  -p "127.0.0.1::8545" \
  --entrypoint /bin/sh \
  "$BESU_IMAGE" \
  /scripts/entrypoint-besu.sh >/dev/null

ASSIGNED=""
for _ in $(seq 1 10); do
  ASSIGNED=$(docker port "$CNAME" 8545/tcp 2>/dev/null | head -1); [ -n "$ASSIGNED" ] && break; sleep 1
done
PORT="${ASSIGNED##*:}"
[ -n "$PORT" ] || die "no host port assigned ('$ASSIGNED')"
RPC="http://127.0.0.1:${PORT}"
echo "    rpc        : $RPC"

echo "==> waiting for RPC (entrypoint waits for a non-empty key, then execs Besu)"
up=0
for i in $(seq 1 90); do
  if cast rpc eth_chainId --rpc-url "$RPC" >/dev/null 2>&1; then up=1; break; fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$CNAME"; then
    docker logs "$CNAME" 2>&1 | tail -25; die "container exited before serving RPC"
  fi
  sleep 1
done
[ "$up" = 1 ] || { docker logs "$CNAME" 2>&1 | tail -25; die "RPC did not come up in 90s"; }
echo "    RPC up after ${i}s"

rc=0

# Isolation must be MEASURED, not assumed: the entrypoint builds its own besu command line, so
# confirm from the running process that discovery is off and the RPC is loopback-published only.
CMDLINE=$(docker exec "$CNAME" sh -c 'tr "\0" " " < /proc/1/cmdline' 2>/dev/null || echo "")
echo "  INFO container cmdline: ${CMDLINE:0:150}"
PEERS=$(cast rpc net_peerCount --rpc-url "$RPC" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()))' 2>/dev/null || echo "?")
if [ "$PEERS" = "0x0" ]; then echo "  PASS peer count        $PEERS (isolated)"; else fail "peer count $PEERS -- expected 0x0"; rc=1; fi

B0=$(cast rpc eth_getBlockByNumber 0x0 false --rpc-url "$RPC")
H0=$(printf '%s' "$B0" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])')
if [ "$H0" = "$EXPECTED_BLOCK0" ]; then echo "  PASS block0 hash      $H0"; else fail "block0 hash $H0 != $EXPECTED_BLOCK0"; rc=1; fi

N0=$(cast rpc eth_blockNumber --rpc-url "$RPC" | python3 -c 'import json,sys; print(int(json.loads(sys.stdin.read()),16))')
echo "  INFO head at t0        $N0"
echo "==> observing for ${OBSERVE_SECONDS}s (blockperiodseconds=5)"
sleep "$OBSERVE_SECONDS"
N1=$(cast rpc eth_blockNumber --rpc-url "$RPC" | python3 -c 'import json,sys; print(int(json.loads(sys.stdin.read()),16))')
echo "  INFO head at t1        $N1"
if [ "$N1" -gt "$N0" ]; then
  echo "  PASS head advancing    $N0 -> $N1 (+$((N1-N0)) blocks)"
else
  fail "head NOT advancing ($N0 -> $N1): the node has block 0 but is not sealing."
  fail "That is exactly the failure a matching genesis sha256 cannot catch."
  rc=1
fi

# The decisive check: block 1's miner must be the genesis validator. Only that key can seal it.
if [ "$N1" -ge 1 ]; then
  B1=$(cast rpc eth_getBlockByNumber 0x1 false --rpc-url "$RPC")
  M1=$(printf '%s' "$B1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["miner"])')
  if [ "$M1" = "$EXPECTED_VALIDATOR" ]; then
    echo "  PASS block1 miner      $M1  == genesis validator: THIS KEY SEALS THIS CHAIN"
  else
    fail "block1 miner $M1 != $EXPECTED_VALIDATOR"; rc=1
  fi
else
  fail "no block 1 to inspect"; rc=1
fi

echo
if [ "$rc" = 0 ]; then
  echo "==> ALL PASS. deploy.sh -> push-secrets.sh -> verify.sh will produce a sealing node."
else
  echo "==> FAILURES ABOVE. Do not deploy until this passes."
fi
exit "$rc"
