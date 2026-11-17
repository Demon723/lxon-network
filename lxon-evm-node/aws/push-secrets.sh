#!/usr/bin/env bash
# Delivers the QBFT validator key to the running LXON node.
#
# Besu signs QBFT blocks with --node-private-key-file, so this single file is both the
# devp2p identity and the validator identity; its address must match the validator baked
# into besu/genesis.qbft.json's extraData. No password file is needed (unlike geth, which
# had to unlock the etherbase account).
#
# Reads the EIP from the instance tag, scp's the key, and confirms Besu starts sealing.
# The local key never leaves your machine except over this SSH session and is never committed.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SSH_USER="ubuntu"
VALIDATOR="0xfae699d2848957c7c3be67d8c90f0e456419cada"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="$(dirname "$SCRIPT_DIR")"

[ -f "$KEY_FILE" ] || { echo "ERROR: ${KEY_FILE} missing — run ./deploy.sh first" >&2; exit 1; }
[ -s "${NODE_DIR}/geth/privatekey.txt" ] || { echo "ERROR: local geth/privatekey.txt missing/empty" >&2; exit 1; }

EIP=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text)
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: EIP not found" >&2; exit 1; }
echo "==> Pushing validator key to ${EIP}"

scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${NODE_DIR}/geth/privatekey.txt" "${SSH_USER}@${EIP}:/opt/lxon/besu/privatekey.txt"

# Must stay readable by uid 1000 (the container user); on Ubuntu, uid 1000 is 'ubuntu'.
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "chmod 600 /opt/lxon/besu/privatekey.txt && docker ps --format '{{.Names}}' | grep -q lxon-besu-sealer && echo 'besu container running (entrypoint picks the key up within 10s)'"

# The RPC is published on 127.0.0.1 only (and the security group has no rule for 8545),
# so every JSON-RPC check below runs ON the instance over SSH. Do not "fix" this by
# re-opening the port: QBFT here is n=1/f=0, and an exposed qbft_proposeValidatorVote lets
# any stranger vote themselves into the validator set and take the chain.
rpc_on_node() {
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
    "curl -s -m 10 -X POST -H 'content-type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}' http://127.0.0.1:8545"
}

echo "==> Waiting for sealing"
for i in $(seq 1 42); do
  BN=$(rpc_on_node eth_blockNumber '[]' | grep -o '"result":"0x[0-9a-f]*"' | grep -o '0x[0-9a-f]*' || true)
  if [ -n "$BN" ] && [ "$BN" != "0x0" ]; then
    echo "==> Sealing. Current block: ${BN}"
    VALS=$(rpc_on_node qbft_getValidatorsByBlockNumber '["latest"]')
    case "$VALS" in
      *"Method not enabled"*)
        echo "    validator set not readable: QBFT is off the standing RPC API set (intentional)."
        echo "    To inspect it: ssh -i ${KEY_FILE} ${SSH_USER}@${EIP}, then"
        echo "      docker exec lxon-besu-sealer /opt/besu/bin/besu operator ..."
        echo "    or restart Besu once with BESU_RPC_API=ETH,NET,WEB3,DEBUG,TXPOOL,TRACE,QBFT"
        ;;
      *"${VALIDATOR#0x}"*) echo "    validator set: ${VALS}" ;;
      *) echo "    WARNING: expected validator ${VALIDATOR} not in: ${VALS}" >&2 ;;
    esac
    echo "    The chain restarts from genesis on an empty data volume."
    echo "    Never run two sealers for this chain with the same key — they fork."
    exit 0
  fi
  sleep 10
done
echo "ERROR: no blocks after 7 min — check: ssh -i ${KEY_FILE} ${SSH_USER}@${EIP} 'docker logs lxon-besu-sealer --tail 50'" >&2
exit 1
