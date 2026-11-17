#!/bin/sh
# LXON chain (chainId 724) — Geth Clique sealer entrypoint.
# Idempotent: initializes the datadir and imports the sealer key only on first run.
set -e

DATADIR=/data
SEALER=0xfae699d2848957c7c3be67d8c90f0e456419cada

# On remote deployments the sealer key is delivered after provisioning
# (scp'd into the bind-mounted secrets dir). deploy.sh creates an empty
# placeholder so the bind mount exists; wait for real content before starting.
while [ ! -s /secrets/privatekey.txt ]; do
  echo "[geth] waiting for sealer key (deliver with push-secrets.sh)..."
  sleep 10
done

if [ ! -d "$DATADIR/geth/chaindata" ]; then
  echo "[geth] initializing datadir from genesis..."
  geth init --datadir "$DATADIR" /genesis/genesis.json
fi

if ! geth --datadir "$DATADIR" account list 2>/dev/null | grep -qi "fae699d2848957c7c3be67d8c90f0e456419cada"; then
  echo "[geth] importing sealer private key..."
  geth account import --datadir "$DATADIR" --password /secrets/password.txt /secrets/privatekey.txt
fi

exec geth \
  --datadir "$DATADIR" \
  --networkid 724 \
  --nodekey /secrets/nodekey \
  --syncmode full \
  --gcmode archive \
  --nodiscover \
  --ipcdisable \
  --port 30303 \
  --nat none \
  --mine \
  --miner.etherbase "$SEALER" \
  --unlock "$SEALER" \
  --password /secrets/password.txt \
  --allow-insecure-unlock \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.vhosts '*' --http.corsdomain '*' \
  --http.api eth,net,web3,txpool,clique,debug \
  --ws --ws.addr 0.0.0.0 --ws.port 8546 \
  --ws.origins '*' --ws.api eth,net,web3
