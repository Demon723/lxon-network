#!/usr/bin/env bash
# Tears down everything deploy.sh created. Destructive — no undo.
# Usage: ./teardown.sh            (prompts for confirmation)
#        ./teardown.sh --yes     (no prompt)
set -euo pipefail

REGION="${REGION:-eu-north-1}"
NAME="lxon-node"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SG_NAME="lxon-node-sg"

if [ "${1:-}" != "--yes" ]; then
  echo "This will TERMINATE instance ${NAME}, release its EIP, delete SG ${SG_NAME} and key pair ${KEY_NAME}."
  read -r -p "Type 'destroy' to continue: " ans
  [ "$ans" = "destroy" ] || { echo "aborted"; exit 1; }
fi

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
  echo "==> Terminating ${INSTANCE_ID}"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
fi

EIP_ALLOC=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=${NAME}-eip" --query 'Addresses[0].AllocationId' --output text)
if [ -n "$EIP_ALLOC" ] && [ "$EIP_ALLOC" != "None" ]; then
  echo "==> Releasing EIP ${EIP_ALLOC}"
  aws ec2 release-address --region "$REGION" --allocation-id "$EIP_ALLOC"
fi

SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "==> Deleting SG ${SG_ID}"
  aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID"
fi

if aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "==> Deleting key pair ${KEY_NAME}"
  aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"
  rm -f "$KEY_FILE"
fi

echo "==> Done. Volumes marked DeleteOnTermination are gone with the instance."
