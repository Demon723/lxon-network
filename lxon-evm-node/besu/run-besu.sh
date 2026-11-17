#!/usr/bin/env bash
# Single-node, self-sealing Hyperledger Besu QBFT dev chain.
#
#   chainId 724, Cancun EVM at block 0, 5s block period, epoch 30000,
#   sole validator = 0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA (pre-funded in genesis).
#
# The private key is never copied into this repo: the container bind-mounts the existing
# geth key file read-only and Besu reads it as a bare 64-hex file via --node-private-key-file.
#
# Usage:
#   ./run-besu.sh              start (docker run -d), RPC on :8655, WS on :8656
#   RESET=1 ./run-besu.sh      wipe the blockstore first (required when the genesis changes)
#   RPC_PORT=9000 ./run-besu.sh
#
# Regenerate genesis.qbft.json after editing make-operator-config.py:
#   python3 make-operator-config.py && rm -rf out && mkdir out && chmod 777 out
#   docker run --rm -u 1000:1000 -v "$PWD":/work -w /work --entrypoint /opt/besu/bin/besu \
#     hyperledger/besu:latest operator generate-blockchain-config \
#     --config-file=/work/operator-config.json --to=/work/out
#   cp out/genesis.json genesis.qbft.json
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-hyperledger/besu:latest}"
CONTAINER="${CONTAINER:-besu-qbft-dev}"
RPC_PORT="${RPC_PORT:-8655}"
WS_PORT="${WS_PORT:-8656}"
P2P_PORT="${P2P_PORT:-30303}"
GENESIS="${GENESIS:-$DIR/genesis.qbft.json}"
SEALER_KEY="${SEALER_KEY:-/Users/adikamble/lxon/LXON/lxon-evm-node/geth/privatekey.txt}"

[[ -f "$GENESIS" ]]    || { echo "missing genesis file: $GENESIS" >&2; exit 1; }
[[ -f "$SEALER_KEY" ]] || { echo "missing sealer key file: $SEALER_KEY" >&2; exit 1; }

mkdir -p "$DIR/data"
chmod 777 "$DIR/data"                       # besu runs as uid 1000 in the image
if [[ "${RESET:-0}" == "1" ]]; then
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$DIR/data" && mkdir -p "$DIR/data" && chmod 777 "$DIR/data"
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

# QBFT/IBFT namespace is QBFT (note: qbft_getValidatorsAtBlock does not exist in 26.10,
# use qbft_getValidatorsByBlockNumber / qbft_getValidatorsByBlockHash).
# FULL sync mode + revert reasons are required for debug_trace* and for readable reverts.
docker run -d \
  --name "$CONTAINER" \
  -u 1000:1000 \
  -p "${RPC_PORT}:8545" \
  -p "${WS_PORT}:8546" \
  -p "${P2P_PORT}:30303" \
  -v "$GENESIS:/etc/besu/genesis.json:ro" \
  -v "$SEALER_KEY:/key/key.priv:ro" \
  -v "$DIR/data:/var/lib/besu" \
  --entrypoint /opt/besu/bin/besu "$IMAGE" \
  --data-path=/var/lib/besu \
  --genesis-file=/etc/besu/genesis.json \
  --node-private-key-file=/key/key.priv \
  --sync-mode=FULL \
  --revert-reason-enabled \
  --min-gas-price=0 \
  --tx-pool-min-gas-price=0 \
  --rpc-http-enabled=true \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api=ETH,NET,WEB3,DEBUG,TXPOOL,QBFT,ADMIN,MINER,TRACE \
  --rpc-ws-enabled=true \
  --rpc-ws-host=0.0.0.0 \
  --rpc-ws-port=8546 \
  --rpc-ws-api=ETH,NET,WEB3,DEBUG,TXPOOL,QBFT,ADMIN,MINER,TRACE \
  --host-allowlist='*' \
  --rpc-http-cors-origins='*' \
  --logging=INFO

echo "$CONTAINER started; RPC http://127.0.0.1:${RPC_PORT}  WS ws://127.0.0.1:${WS_PORT}"
echo "logs: docker logs -f $CONTAINER"
