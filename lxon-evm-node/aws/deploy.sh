#!/usr/bin/env bash
# LXON single-EC2 deploy — provisions infrastructure and pushes config.
#
# Usage: ./deploy.sh
#
# Creates (tagged, idempotent-ish):
#   - EC2 key pair  lxon-eu-north-1        -> ~/.ssh/lxon-eu-north-1.pem
#   - Security group lxon-node-sg          (22 from SSH_CIDR only; 30303 tcp+udp,
#                                           4000 and 3000 open to the world; 8545/8546
#                                           deliberately NOT opened)
#   - Elastic IP   tagged Name=lxon-node-eip (survives stop/start)
#   - EC2 instance lxon-node (t3.large, Ubuntu 24.04, 150GB gp3)
#
# Then: installs Docker via user-data, waits for SSH, copies the stack to
# /opt/lxon (sealer key NOT included — see push-secrets.sh), writes .env,
# pulls images and starts everything. Geth waits for the sealer key.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
AZ="${REGION}a"
NAME="lxon-node"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SG_NAME="lxon-node-sg"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"
ROOT_GB="${ROOT_GB:-150}"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Resolving Ubuntu 24.04 AMI in ${REGION}"
# This IAM user has no ssm:GetParameter, so the public SSM parameter store is
# off-limits — resolve via the public AMI catalog (Canonical owner id) instead.
AMI=$(aws ec2 describe-images --region "$REGION" --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "    AMI: ${AMI}"

# SSH ingress CIDR. NOTE: do NOT derive this from checkip.amazonaws.com —
# this user's ISP NATs TCP/22 egress through a different address than TCP/443,
# so the checkip IP is NOT the IP your SSH connections come from. Restrict to
# your ISP's range instead (found via auth.log while temporarily open), or
# pass your own: SSH_CIDR=x.y.z.0/24 ./deploy.sh
SSH_CIDR="${SSH_CIDR:-42.104.0.0/16}"
echo "==> SSH ingress CIDR: ${SSH_CIDR}"

if aws ec2 describe-instances --region "$REGION" \
     --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
     --query 'Reservations[].Instances[].InstanceId' --output text | grep -q i-; then
  echo "ERROR: an instance named ${NAME} already exists. Run ./teardown.sh first." >&2
  exit 1
fi

echo "==> Key pair ${KEY_NAME}"
if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "    created -> ${KEY_FILE}"
else
  echo "    exists (using ${KEY_FILE})"
  [ -f "$KEY_FILE" ] || { echo "ERROR: key pair exists in AWS but ${KEY_FILE} is missing locally." >&2; exit 1; }
fi

echo "==> Security group ${SG_NAME}"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
    --description "LXON single node" --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${SSH_CIDR},Description=admin-ssh}]" >/dev/null
  # NOTE: no 8545/8546 ingress. Besu publishes the RPC on 127.0.0.1 only, and opening the
  # ports would be a chain takeover, not an inconvenience: QBFT is n=1/f=0 here, so one
  # anonymous qbft_proposeValidatorVote makes the caller a consensus validator. Operators
  # use an SSH tunnel (see README.md).
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --ip-permissions \
                     "IpProtocol=tcp,FromPort=30303,ToPort=30303,IpRanges=[{CidrIp=0.0.0.0/0}]" \
                     "IpProtocol=udp,FromPort=30303,ToPort=30303,IpRanges=[{CidrIp=0.0.0.0/0}]" \
                     "IpProtocol=tcp,FromPort=4000,ToPort=4000,IpRanges=[{CidrIp=0.0.0.0/0}]" \
                     "IpProtocol=tcp,FromPort=3000,ToPort=3000,IpRanges=[{CidrIp=0.0.0.0/0}]" >/dev/null
  echo "    created ${SG_ID}"
else
  echo "    exists ${SG_ID}"
fi

echo "==> Elastic IP"
EIP_ALLOC=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=${NAME}-eip" --query 'Addresses[0].AllocationId' --output text 2>/dev/null || true)
if [ -z "$EIP_ALLOC" ] || [ "$EIP_ALLOC" = "None" ]; then
  EIP_ALLOC=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
  aws ec2 create-tags --region "$REGION" --resources "$EIP_ALLOC" --tags "Key=Name,Value=${NAME}-eip" "Key=Project,Value=lxon" >/dev/null
fi
EIP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$EIP_ALLOC" --query 'Addresses[0].PublicIp' --output text)
echo "    ${EIP} (${EIP_ALLOC})"

echo "==> Launching ${INSTANCE_TYPE} instance"
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
  --placement "AvailabilityZone=${AZ}" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${ROOT_GB},VolumeType=gp3,DeleteOnTermination=true}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}},{Key=Project,Value=lxon}]" \
  --user-data file://"${SCRIPT_DIR}/user-data.sh" \
  --query 'Instances[0].InstanceId' --output text)
echo "    ${INSTANCE_ID}"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 associate-address --region "$REGION" --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" >/dev/null
echo "==> EIP ${EIP} associated"

echo "==> Waiting for SSH (user-data installs Docker, ~2-4 min)"
for i in $(seq 1 60); do
  if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
      "${SSH_USER}@${EIP}" true 2>/dev/null; then break; fi
  sleep 10
  [ "$i" = "60" ] && { echo "ERROR: SSH not reachable after 10 min" >&2; exit 1; }
done
echo "    SSH ok"

echo "==> Waiting for Docker on host"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  'for i in $(seq 1 90); do docker info >/dev/null 2>&1 && exit 0; sleep 10; done; echo "docker never became ready"; exit 1'
echo "    docker ok"

echo "==> Generating fresh secrets (.env)"
DB_PASSWORD=$(openssl rand -hex 16)
SECRET_KEY_BASE=$(openssl rand -hex 64)

echo "==> Pushing stack config to ${REMOTE_DIR}"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "sudo mkdir -p ${REMOTE_DIR}/besu && sudo chown -R ${SSH_USER}:${SSH_USER} ${REMOTE_DIR}"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${NODE_DIR}/besu/genesis.qbft.json" "${NODE_DIR}/besu/entrypoint-besu.sh" \
  "${SSH_USER}@${EIP}:${REMOTE_DIR}/besu/"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${SCRIPT_DIR}/docker-compose.aws.yml" "${SSH_USER}@${EIP}:${REMOTE_DIR}/docker-compose.yml"

# Placeholder so the bind mount exists; push-secrets.sh fills it with the real validator
# key (Besu's entrypoint waits until the file is non-empty). Besu runs as uid 1000 inside
# the container and the bind mount preserves host ownership, so this file must be owned by
# uid 1000 -- on Ubuntu the default 'ubuntu' user *is* uid 1000. If you change SSH_USER or
# use an AMI where the login user has another uid, chown this file to 1000 instead.
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "touch ${REMOTE_DIR}/besu/privatekey.txt && chmod 600 ${REMOTE_DIR}/besu/privatekey.txt"

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "printf 'EIP=${EIP}\nDB_PASSWORD=${DB_PASSWORD}\nSECRET_KEY_BASE=${SECRET_KEY_BASE}\n' > ${REMOTE_DIR}/.env && chmod 600 ${REMOTE_DIR}/.env"

echo "==> Pulling images and starting stack"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "cd ${REMOTE_DIR} && docker compose pull && docker compose up -d"

cat <<EOF

==> Provisioned. EIP: ${EIP}

Next step (delivers the validator key — required before Besu will seal):

    ./push-secrets.sh

Then verify (the RPC is loopback-only; tunnel it):

    ssh -i ~/.ssh/lxon-${REGION}.pem -N -L 8545:127.0.0.1:8545 ${SSH_USER}@${EIP} &
    curl -X POST -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      http://127.0.0.1:8545

Endpoints:
    RPC:      127.0.0.1:8545 on the instance only — SSH tunnel required (chainId 724)
    WS:       127.0.0.1:8546, same
    API:      http://${EIP}:4000/api/v2/stats
    Explorer: http://${EIP}:3000

EOF
