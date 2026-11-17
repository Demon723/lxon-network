#!/usr/bin/env bash
# Generate the sealer key WHERE IT WILL BE USED -- on the instance. Nothing secret crosses back:
# the ceremony returns the validator's PUBLIC point and derives the address locally.
#
#   ./NewSealerKeyOnInstance.sh              # EIP resolved from the AWS tag
#   ./NewSealerKeyOnInstance.sh 1.2.3.4
#
# Run this before deploy.sh pushes a genesis, or re-push the rotated genesis afterwards: QBFT reads
# its validator set from genesis extraData, so a new key is only usable by a chain that was told
# about that key at block 0.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SSH_USER="ubuntu"
REMOTE_KEY="/opt/lxon/besu/privatekey.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EIP="${1:-}"
if [ -z "$EIP" ]; then
  EIP=$(aws ec2 describe-addresses --region "$REGION" \
    --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text 2>/dev/null)
fi
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: pass the EIP as \$1 (no tagged address found)" >&2; exit 2; }
[ -f "$KEY_FILE" ] || { echo "ERROR: $KEY_FILE missing -- run deploy.sh first" >&2; exit 2; }

ssh_q() { ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${SSH_USER}@${EIP}" "$@"; }

echo "==> Instance reachable, generating key on it"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q "${SCRIPT_DIR}/remote_genkey.py" "${SSH_USER}@${EIP}:/tmp/remote_genkey.py"
OUT=$(ssh_q "umask 077 && python3 /tmp/remote_genkey.py $REMOTE_KEY" 2>&1)
printf '%s\n' "$OUT" | grep -v PUBPOINT
ssh_q "rm -f /tmp/remote_genkey.py"

POINT=$(printf '%s\n' "$OUT" | sed -n 's/^VALIDATOR_PUBPOINT //p')
[ -n "$POINT" ] || { echo "ERROR: no public point returned; nothing derived." >&2; exit 1; }

echo "==> Deriving the validator address from the public point (local, no secret involved)"
ADDR=$(node "${SCRIPT_DIR}/pubkey_to_address.js" "$POINT")
echo "    new validator address : $ADDR"

echo "==> Confirming the key file is readable only by the Besu uid"
ssh_q "stat -c '    %n mode=%a uid=%u size=%s' $REMOTE_KEY"
ssh_q "test \$(stat -c '%a' $REMOTE_KEY) = 600 && test \$(stat -c '%u' $REMOTE_KEY) = 1000 \
        || { echo 'ERROR: key file must be mode 600 and uid 1000 (Besu runs as 1000)'; exit 1; }"
# Existence check without printing content: does Besu's expected shape hold (64 hex + newline)?
ssh_q "wc -c < $REMOTE_KEY | grep -q '^65\$' || { echo 'ERROR: key file is not 64 hex + newline'; exit 1; }"
echo "    ok: 65 bytes = 64 hex chars + newline, 0600, uid 1000"

cat <<EOF

==> Next: put THIS address into genesis, or the node will not be the validator.

  cd $SCRIPT_DIR
  ./RotateSealerGenesis.sh $ADDR
  # it prints the new block-0 hash; pass both forward:
  GENESIS_FILE=<the genesis.sealer-*.json it writes> ./deploy.sh
  EXPECTED_BLOCK0=<new hash> ./verify.sh

  If you would rather keep the original identity (0xFaE699d2… is the validator baked into the
  recovered genesis and the address the docs quote), then do not rotate: the file just written
  is unusable against that genesis and should be removed.

  Back it up encrypted before the box is ever stopped:
  ./BackupSealerKeySecurely.sh $EIP
EOF
