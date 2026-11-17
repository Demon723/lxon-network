#!/usr/bin/env bash
# Prove a genesis file actually boots Besu and produces the expected block 0 -- BEFORE
# spending AWS credits on it.
#
# Why this exists: deploy.sh only checks the genesis file's sha256. A matching sha proves
# the file is the one recovered from the lost host; it does NOT prove Besu will accept it or
# that the resulting block 0 is the one the manifest recorded. verify.sh checks that, but
# only after an instance exists. This closes the gap locally.
#
# No key material is used or created: block 0 (genesis) needs no sealer, and Besu generates
# its own throwaway p2p node key when --node-private-key-file is omitted. The node will log
# that it is not a validator and will not seal -- that is expected and irrelevant here.
#
#   ./ProveGenesisLocally.sh                      # production genesis, expected block 0
#   EXPECTED_BLOCK0=0x... ./ProveGenesisLocally.sh GENESIS=genesis/genesis.qbft.sealer-abcd1234.json
#
# Requires: docker daemon up, hyperledger/besu:26.10.0 (907 MB, pull if absent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENESIS="${GENESIS:-${GENESIS_FILE:-${SCRIPT_DIR}/genesis/genesis.qbft.json}}"
BESU_IMAGE="${BESU_IMAGE:-hyperledger/besu:26.10.0}"
EXPECTED_CHAINID="${EXPECTED_CHAINID:-0x2d4}"
EXPECTED_BLOCK0="${EXPECTED_BLOCK0:-0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588}"
HOST_PORT="${HOST_PORT:-}"          # empty = let docker pick an ephemeral port
CNAME="lxon-genesis-proof"

# State lives under ~/.lxon/runs, NOT /tmp: a startup sweep deletes /tmp/lxon-* and has
# already eaten a live run directory once.
WORK="${WORK:-$HOME/.lxon/runs/genesis-proof}"

fail() { echo "  FAIL $*" >&2; }
die()  { fail "$*"; cleanup; exit 1; }
cleanup() {
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
  # Throwaway chain data goes with the container. This disk runs near full, so do not leave
  # a Besu database behind. KEEP_WORK=1 preserves it for inspection.
  [ "${KEEP_WORK:-0}" = 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> ProveGenesisLocally"
echo "    genesis         : $GENESIS"
echo "    image           : $BESU_IMAGE"
echo "    expected chainid: $EXPECTED_CHAINID"
echo "    expected block0 : $EXPECTED_BLOCK0"

[ -f "$GENESIS" ] || die "genesis file not found: $GENESIS"

# Refuse to inherit another node's state: no stale container of this name may exist, and if a
# fixed HOST_PORT was requested it must be free. A leftover process on the port makes this
# proof read someone else's chain and pass for the wrong reason.
#
# By default the host port is EPHEMERAL (docker assigns it). A fixed port made back-to-back
# runs fail: the trap removes the container, but docker-proxy holds the port for a moment, so
# the next run's own guard fired on a listener that was already going away.
PORT_OPT="127.0.0.1::8545"
if [ -n "${HOST_PORT:-}" ]; then
  if lsof -nP -iTCP:"$HOST_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "port $HOST_PORT is already in use -- something is listening. Unset HOST_PORT for an ephemeral one."
  fi
  PORT_OPT="127.0.0.1:${HOST_PORT}:8545"
fi
if docker ps -a --format '{{.Names}}' | grep -qx "$CNAME"; then
  echo "    removing stale container $CNAME"
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
fi
rm -rf "$WORK"
mkdir -p "$WORK/besu-data"
# Besu runs as a non-root uid inside the image and /var/lib/besu is not writable there
# ("Failed to create data directory"), so it must be a bind mount the container can write.
# 0777 on a throwaway dir under ~/.lxon/runs; the chain data is deleted with $WORK below.
chmod 0777 "$WORK/besu-data"

docker run -d --name "$CNAME" \
  -v "$GENESIS:/etc/besu/genesis.json:ro" \
  -v "$WORK/besu-data:/var/lib/besu" \
  -p "$PORT_OPT" \
  "$BESU_IMAGE" \
  --data-path=/var/lib/besu \
  --genesis-file=/etc/besu/genesis.json \
  --sync-mode=FULL \
  --min-gas-price=0 \
  --p2p-port=30303 \
  --max-peers=0 \
  --rpc-http-enabled=true \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api=ETH,NET,WEB3 \
  --host-allowlist=* \
  --logging=INFO >/dev/null

# Discover the port docker actually assigned (form: 127.0.0.1:NNNNN). Retry briefly: the
# mapping can be empty for a moment right after `docker run -d` returns.
ASSIGNED=""
for _ in $(seq 1 10); do
  ASSIGNED=$(docker port "$CNAME" 8545/tcp 2>/dev/null | head -1)
  [ -n "$ASSIGNED" ] && break
  sleep 1
done
HOST_PORT_ACTUAL="${ASSIGNED##*:}"
[ -n "$HOST_PORT_ACTUAL" ] || die "could not determine the assigned host port from: '$ASSIGNED'"
RPC="http://127.0.0.1:${HOST_PORT_ACTUAL}"

echo "==> waiting for RPC on $RPC"
up=0
for i in $(seq 1 60); do
  if cast rpc eth_chainId --rpc-url "$RPC" >/dev/null 2>&1; then up=1; break; fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$CNAME"; then
    echo "---- container exited early; last logs ----"
    docker logs "$CNAME" 2>&1 | tail -25
    die "Besu exited before serving RPC"
  fi
  sleep 1
done
[ "$up" = 1 ] || { docker logs "$CNAME" 2>&1 | tail -25; die "RPC did not come up in 60s"; }
echo "    RPC up after ${i}s"

rc=0

# `cast rpc` prints the JSON-encoded result, i.e. "0x2d4" WITH the quotes, so a raw string
# compare against 0x2d4 fails on a healthy node. Decode it. (verify.sh does the same via sed.)
GOT_CHAINID=$(cast rpc eth_chainId --rpc-url "$RPC" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()))')
if [ "$GOT_CHAINID" = "$EXPECTED_CHAINID" ]; then
  echo "  PASS chainId          $GOT_CHAINID"
else
  fail "chainId          got $GOT_CHAINID, expected $EXPECTED_CHAINID"; rc=1
fi

# Read block 0 by field NAME, never by grepping a 64-hex token out of the text receipt:
# that yields the blockHash and hangs the reader.
B0=$(cast rpc eth_getBlockByNumber 0x0 false --rpc-url "$RPC")
GOT_HASH=$(printf '%s' "$B0" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])')
if [ "$GOT_HASH" = "$EXPECTED_BLOCK0" ]; then
  echo "  PASS block0 hash      $GOT_HASH"
else
  fail "block0 hash      got $GOT_HASH"; fail "                 expected $EXPECTED_BLOCK0"; rc=1
fi

# Cross-check the fields verify.sh and the manifest care about.
chk() { # $1=json path  $2=expected  $3=label
  got=$(printf '%s' "$B0" | python3 -c "import json,sys; print(json.load(sys.stdin)$1)")
  if [ "$got" = "$2" ]; then echo "  PASS $3 $got"
  else fail "$3 got $got, expected $2"; rc=1; fi
}
chk "['number']"          "0x0"          "block0 number    "
chk "['gasLimit']"        "0x1c9c380"    "block0 gasLimit  "
chk "['timestamp']"       "0x655c0000"   "block0 timestamp "

# Reported, NOT asserted. A matching block-0 hash is keccak over the entire RLP header, so it
# already proves every field including these. Note the miner of a QBFT genesis block is the
# ZERO address -- no sealer produced block 0 -- so asserting the validator address here was
# wrong and failed a perfectly healthy chain on the first run.
info() { printf '  INFO %s %s\n' "$2" "$(printf '%s' "$B0" | python3 -c "import json,sys; print(json.load(sys.stdin)$1)")"; }
info "['miner']"       "block0 miner     "
info "['parentHash']"  "block0 parentHash"
info "['stateRoot']"   "block0 stateRoot "

EXTRA=$(printf '%s' "$B0" | python3 -c 'import json,sys; print(json.load(sys.stdin)["extraData"])')
GOT_SHA=$(shasum -a 256 "$GENESIS" | awk '{print $1}')
echo "  INFO genesis sha256   $GOT_SHA"
echo "  INFO block0 extraData ${EXTRA:0:20}… (${#EXTRA} chars)"

if [ "$rc" = 0 ]; then
  echo
  echo "==> ALL PASS. This genesis boots Besu ${BESU_IMAGE##*:} and yields the recorded block 0."
  echo "    Safe to deploy: deploy.sh + verify.sh will see the same chain identity."
else
  echo
  echo "==> FAILURES ABOVE. Do NOT deploy this genesis -- it does not reproduce the recorded"
  echo "    chain identity. Fix the file or pass the EXPECTED_BLOCK0 that belongs to it."
fi
exit "$rc"
