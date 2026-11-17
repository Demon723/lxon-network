#!/bin/sh
set -eu

KEY="${NODE_KEY:?NODE_KEY must point at the private key file for this node}"
DATA="${BESU_DATA_PATH:-/var/lib/besu}"
NAME="${BESU_NODE_NAME:?BESU_NODE_NAME is required}"
GENESIS="${BESU_GENESIS:-/etc/besu/genesis.json}"
P2P_PORT="${BESU_P2P_PORT:-30303}"
# Testbed only: QBFT is needed for qbft_getValidatorsByBlockNumber and for
# qbft_proposeValidatorVote, ADMIN for admin_addPeer/admin_nodeInfo. The production
# RPC deliberately exposes neither -- on n=1/f=0 a single anonymous vote is a takeover.
BESU_API="${BESU_RPC_API:-ETH,NET,WEB3,DEBUG,TXPOOL,QBFT,ADMIN,TRACE}"
BESU_HOSTS="${BESU_RPC_HOST_ALLOWLIST:-*}"
BOOTNODES=""
[ -n "${BESU_BOOTNODES:-}" ] && BOOTNODES="--bootnodes=${BESU_BOOTNODES}"

# Fail fast where the failure is silent otherwise. The compose file used to express this with
# `${BOOTNODE_1:?...}`, but Compose interpolates every service at file load, so that one variable
# was required for `down`, `ps` and `logs` too -- it blocked teardown of a running stack on a host
# with no BOOTNODE_1 exported, which is exactly the moment an operator most needs those commands.
# The requirement belongs to a node STARTING, not to a file being read, so it lives here. A
# validator that comes up with no bootnodes does not error -- it just sits at peers=0 forever and
# looks like a consensus failure, so this must be a hard exit.
if [ "${BESU_IS_BOOTNODE:-false}" != "true" ] && [ -z "${BESU_BOOTNODES:-}" ]; then
  echo "BOOTNODE ERROR: $NAME is not the bootnode and BESU_BOOTNODES is empty." >&2
  echo "  run ./capture-enode.sh, export BOOTNODE_1, then re-run up (see README bring-up)." >&2
  exit 1
fi

i=0
while [ ! -s "$KEY" ] && [ "$i" -lt 60 ]; do i=$((i + 1)); sleep 1; done
[ -s "$KEY" ] || { echo "KEY ERROR: $NAME has no key at $KEY" >&2; exit 1; }

# JVM memory comes from JAVA_OPTS only. There is deliberately no `--Xmx` here: Besu has no such
# option and picocli aborts the node ("Unknown option: '--Xmx=320m'"), so adding it would stop
# every node in the testbed from starting. The compose anchor sets JAVA_OPTS and the hard
# container ceiling; this script must not fight either.
exec /opt/besu/bin/besu \
  --data-path="$DATA" \
  --genesis-file="$GENESIS" \
  --node-private-key-file="$KEY" \
  --logging=INFO \
  --sync-mode=FULL \
  --min-gas-price=0 \
  --tx-pool-min-gas-price=0 \
  --p2p-port="$P2P_PORT" \
  --max-peers=25 \
  --rpc-http-enabled=true \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api="$BESU_API" \
  --host-allowlist="$BESU_HOSTS" \
  $BOOTNODES
