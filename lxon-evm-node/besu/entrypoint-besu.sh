#!/bin/sh
# Compose entrypoint for the LXON QBFT sealer (Besu).
#
# On remote deployments the validator key is delivered after provisioning
# (push-secrets.sh scp's it onto the bind-mounted file), so an empty placeholder
# exists at boot. Besu aborts on an unreadable/empty key file, therefore wait for
# real content before starting.
#
# Besu runs as uid 1000 in the image; the compose service sets `user: "1000:1000"`.
#
# RPC exposure policy (2026-10-20):
#   - Only ETH,NET,WEB3,DEBUG,TXPOOL,TRACE are enabled. ADMIN, QBFT and MINER are NOT:
#     this chain is QBFT n=1/f=0, so a single qbft_proposeValidatorVote from any HTTP
#     client makes the caller a consensus validator — i.e. full chain takeover. Do votes
#     over an SSH tunnel with a temporary `--rpc-http-api` addition instead.
#   - TRACE and DEBUG stay on because Blockscout needs them (trace_transactions,
#     debug_traceBlock*); they are read-only.
#   - The compose file publishes 8545/8546 on 127.0.0.1 only, and the security group has
#     no rule for either port, so the only path in is from the docker network (Blockscout)
#     or an SSH tunnel (operators).
#   - Host allowlist is pinned; Blockscout connects as http://besu-sealer:8545, a tunnel
#     arrives as localhost/127.0.0.1.

KEY=/key/key.priv
DATA=/var/lib/besu

while [ ! -s "$KEY" ]; do
  echo "[besu] waiting for validator key (deliver with aws/push-secrets.sh)..."
  sleep 10
done

BESU_API="${BESU_RPC_API:-ETH,NET,WEB3,DEBUG,TXPOOL,TRACE}"
BESU_HOSTS="${BESU_RPC_HOST_ALLOWLIST:-localhost,127.0.0.1,besu-sealer}"

exec /opt/besu/bin/besu \
  --data-path="$DATA" \
  --genesis-file=/etc/besu/genesis.json \
  --node-private-key-file="$KEY" \
  --sync-mode=FULL \
  --revert-reason-enabled \
  --min-gas-price=0 \
  --tx-pool-min-gas-price=0 \
  --p2p-port=30303 \
  --max-peers=25 \
  --rpc-http-enabled=true \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api="$BESU_API" \
  --rpc-ws-enabled=true \
  --rpc-ws-host=0.0.0.0 \
  --rpc-ws-port=8546 \
  --rpc-ws-api="$BESU_API" \
  --host-allowlist="$BESU_HOSTS" \
  --logging=INFO
