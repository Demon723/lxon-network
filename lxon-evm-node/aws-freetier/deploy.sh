#!/usr/bin/env bash
# LXON free-tier node provisioning: one t4g Besu sealer on chain 724, in account 044409363656.
#
# Read ./preflight.sh first: this script spends real AWS credits, and on the post-July-2025
# free plan credits are the only budget (up to \$200, and the account closes 6 months after it
# opens whether or not the credits are gone).
#
#   ./preflight.sh && ./deploy.sh
#   SSH_CIDR=1.2.3.0/24 INSTANCE_TYPE=t4g.small ./deploy.sh     # 2 GiB if 1 GiB proves tight
#
# Deliberate carry-overs from ../aws/deploy.sh: same tags, same key-pair name, same loopback
# RPC policy, so ../aws/push-secrets.sh works against this box without editing it.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
AZ="${AZ:-${REGION}a}"
EXPECTED_ACCOUNT="${EXPECTED_ACCOUNT:-044409363656}"
NAME="lxon-node-ft"
EIP_TAG="lxon-node-eip"          # unchanged on purpose: ../aws/push-secrets.sh looks this up
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SG_NAME="lxon-node-sg"
INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.micro}"
ROOT_GB="${ROOT_GB:-20}"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="$(dirname "$SCRIPT_DIR")"
# GENESIS_FILE is the name every other script in this kit and the README tell you to set;
# GENESIS is accepted as an alias. Before this, GENESIS_FILE= was silently ignored and a
# "rotated" deploy launched the PRODUCTION genesis -- caught only later by verify.sh's
# block-0 check, i.e. after an instance existed and credits were spent.
GENESIS="${GENESIS:-${GENESIS_FILE:-${SCRIPT_DIR}/genesis/genesis.qbft.json}}"
[ -n "${GENESIS_FILE:-}" ] && [ -n "${GENESIS:-}" ] && [ "$GENESIS" != "$GENESIS_FILE" ] && {
  echo "ERROR: both GENESIS ($GENESIS) and GENESIS_FILE ($GENESIS_FILE) are set and disagree." >&2
  echo "       Set one of them. Refusing to guess which chain identity you meant." >&2
  exit 1
}
EXPECTED_GENESIS_SHA="a779acefd0014caf9cfa50d93151bc1d2cd3b07c22c3d16952ec0917282bca20"

# ---- hard gates, before a single AWS write -----------------------------------------------
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
[ "$ACCOUNT" = "$EXPECTED_ACCOUNT" ] || {
  echo "ERROR: credentials are for account ${ACCOUNT}, not ${EXPECTED_ACCOUNT}. Aborting before any write." >&2
  exit 1
}
GOT_SHA=$(shasum -a 256 "$GENESIS" | awk '{print $1}')
if [ "$GOT_SHA" = "$EXPECTED_GENESIS_SHA" ]; then
  echo "==> Genesis: recovered production file (sha ${GOT_SHA:0:12}…), validator 0xFaE699d2…,"
  echo "    block 0 0x6c931dff… -- this restarts chain 724 under its old identity."
  DEFAULT_GENESIS=1
elif basename "$GENESIS" | grep -q '^genesis\.qbft\.sealer-[0-9a-fA-F]\{8\}\.json$'; then
  DEFAULT_GENESIS=0
  [ -n "${EXPECTED_BLOCK0:-}" ] || {
    echo "ERROR: deploying a ROTATED genesis ($(basename "$GENESIS")) without EXPECTED_BLOCK0." >&2
    echo "RotateSealerGenesis.sh prints the new block-0 hash; verify.sh cannot tell a rotated chain" >&2
    echo "from a broken one without it. Re-run as:" >&2
    echo "    EXPECTED_BLOCK0=<hash> GENESIS_FILE=$GENESIS ./deploy.sh" >&2
    exit 1
  }
  echo "==> Genesis: rotated-validator file (sha ${GOT_SHA:0:12}…), new block 0 ${EXPECTED_BLOCK0:0:12}…"
  echo "    This is a NEW chain identity: the old escrow, the old contract addresses and the old"
  echo "    block hashes are unrecoverable either way, but nothing may quote the old block 0."
else
  echo "ERROR: ${GENESIS} is neither the recovered production genesis (sha ${GOT_SHA:0:12}… does" >&2
  echo "       not match ${EXPECTED_GENESIS_SHA:0:12}…) nor a genesis emitted by" >&2
  echo "       RotateSealerGenesis.sh. Refusing to start a chain on an unaccounted genesis." >&2
  exit 1
fi

SSH_CIDR="${SSH_CIDR:-42.104.0.0/16}"
echo "==> ${INSTANCE_TYPE} in ${REGION}, root ${ROOT_GB} GB gp3 encrypted, SSH from ${SSH_CIDR}"
echo "    (SSH_CIDR is NOT derived from checkip: this ISP NATs TCP/22 out a different address"
echo "     than TCP/443, so the checkip answer is the wrong rule. Pass your own /16 if it moved.)"

echo "==> Resolving Ubuntu 24.04 arm64 AMI (Graviton)"
AMI=$(aws ec2 describe-images --region "$REGION" --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "    AMI: ${AMI}"

if aws ec2 describe-instances --region "$REGION" \
     --filters "Name=tag:Project,Values=lxon" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
     --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | grep -q i-; then
  echo "ERROR: an lxon-tagged instance already exists in ${REGION}. This plan is a credit-budget" >&2
  echo "plan; a second node is a second bill. Run ./teardown-into.sh or destroy it deliberately first." >&2
  exit 1
fi

echo "==> Key pair ${KEY_NAME}"
# GUARD ADDED 2026-11-03. The create branch used `> "$KEY_FILE"`, which truncates first: with no
# lxon-eu-north-1 key pair registered in eu-north-1 it would have silently destroyed a pre-existing
# 0600 private key dated Oct 19, whose only copy was that file. Never overwrite a key you did not
# just generate.
if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  if [ -s "$KEY_FILE" ]; then
    echo "ERROR: $KEY_FILE already exists and AWS has no key pair named $KEY_NAME in $REGION." >&2
    echo "       Creating one would overwrite that private key and the old one would be unrecoverable." >&2
    echo "       Move it aside (mv $KEY_FILE $KEY_FILE.bak) or choose KEY_NAME=<new-name>, then re-run." >&2
    exit 1
  fi
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "    created -> $KEY_FILE"
else
  echo "    exists"
  [ -f "$KEY_FILE" ] || { echo "ERROR: key pair exists in AWS but $KEY_FILE is missing locally." >&2; exit 1; }
  # The running us-east-1 node is unreachable precisely because its key pair has no matching local
  # private key, and nothing checked that until SSH failed. Check before provisioning, not after the
  # instance is billing.
  #
  # METHOD MATTERS. The first version compared EC2's KeyFingerprint against SHA-1 of
  # SubjectPublicKeyInfo DER. That is not the same encoding AWS hashes, so it reported a mismatch
  # for a key pair AWS had generated both halves of -- a false alarm that stopped the deploy.
  # `--include-public-key` gives the OpenSSH public half directly, and `ssh-keygen -y` derives the
  # same thing from the private file, so the comparison is exact with no hash convention to guess.
  AWS_PUB=$(aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" \
              --include-public-key --query 'KeyPairs[0].PublicKey' --output text 2>/dev/null || true)
  LOCAL_PUB=$(ssh-keygen -y -f "$KEY_FILE" 2>/dev/null | awk '{print $1" "$2}' || true)
  AWS_PUB_N=$(printf '%s' "$AWS_PUB" | awk '{print $1" "$2}')
  if [ -z "$AWS_PUB_N" ] || [ "$AWS_PUB_N" = " " ]; then
    echo "ERROR: could not read the public key AWS holds for $KEY_NAME; refusing to launch an" >&2
    echo "       instance whose login path cannot be verified." >&2
    exit 1
  fi
  if [ -z "$LOCAL_PUB" ]; then
    echo "ERROR: $KEY_FILE is not a readable private key." >&2
    exit 1
  fi
  if [ "$LOCAL_PUB" = "$AWS_PUB_N" ]; then
    echo "    public half matches $KEY_FILE"
  else
    echo "ERROR: $KEY_FILE does NOT correspond to key pair $KEY_NAME in $REGION." >&2
    echo "       The instance would launch unreachable, exactly like i-0c0426d9265615719." >&2
    echo "       See ./match-keypair.py to find which local key, if any, matches." >&2
    exit 1
  fi
fi

echo "==> Security group ${SG_NAME}"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
    --description "LXON free-tier node" --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${SSH_CIDR},Description=admin-ssh}]" >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --ip-permissions \
      "IpProtocol=tcp,FromPort=30303,ToPort=30303,IpRanges=[{CidrIp=0.0.0.0/0,Description=devp2p-tcp}]" \
      "IpProtocol=udp,FromPort=30303,ToPort=30303,IpRanges=[{CidrIp=0.0.0.0/0,Description=devp2p-udp}]" >/dev/null
  echo "    created $SG_ID  (22 gated, 30303 open, NO 8545/8546/3000/4000)"
else
  echo "    exists $SG_ID"
fi

echo "==> Elastic IP"
EIP_ALLOC=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=${EIP_TAG}" --query 'Addresses[0].AllocationId' --output text 2>/dev/null || true)
if [ -z "$EIP_ALLOC" ] || [ "$EIP_ALLOC" = "None" ]; then
  EIP_ALLOC=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
  aws ec2 create-tags --region "$REGION" --resources "$EIP_ALLOC" \
    --tags "Key=Name,Value=${EIP_TAG}" "Key=Project,Value=lxon" >/dev/null
fi
EIP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$EIP_ALLOC" --query 'Addresses[0].PublicIp' --output text)
echo "    $EIP ($EIP_ALLOC)"

echo "==> Launching ${INSTANCE_TYPE}"
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
  --placement "AvailabilityZone=${AZ}" \
  --metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpProtocolIpv6=disabled" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${ROOT_GB},VolumeType=gp3,Encrypted=true,DeleteOnTermination=false}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}},{Key=Project,Value=lxon},{Key=Plan,Value=free-tier}]" \
  --user-data "file://${SCRIPT_DIR}/user-data.sh" \
  --query 'Instances[0].InstanceId' --output text)
echo "    $INSTANCE_ID"
# DeleteOnTermination=false is a change from the old script: the last chain database died with
# an instance that had DeleteOnTermination=true semantics for the operator's purposes. A snapshot
# is now the explicit step (see README step 7), but the volume survives an accidental terminate.

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 associate-address --region "$REGION" --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" >/dev/null
echo "==> EIP $EIP associated"

echo "==> Waiting for SSH (user-data installs Docker + 2 GiB swap, ~2-5 min)"
for i in $(seq 1 60); do
  if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
      "${SSH_USER}@${EIP}" true 2>/dev/null; then break; fi
  sleep 10
  [ "$i" = 60 ] && { echo "ERROR: SSH not reachable after 10 min" >&2; exit 1; }
done
echo "    SSH ok"

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  'for i in $(seq 1 90); do docker info >/dev/null 2>&1 && exit 0; sleep 10; done; echo "docker never became ready"; exit 1'
echo "==> Docker ok"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  # Column is PRIO, not PRIORITY -- `swapon --show=...,PRIORITY` errors out, and because this line
  # had a `|| echo "NO SWAP"` fallback it reported a MISSING 2 GiB swapfile on a node that had one
  # working fine. A check that cries wolf is worse than no check.
  'free -h | head -2; swapon --show=NAME,TYPE,SIZE,USED,PRIO || echo "swapon listed no devices"'

echo "==> Pushing stack (genesis verified at ${EXPECTED_GENESIS_SHA:0:12}…)"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "sudo mkdir -p ${REMOTE_DIR}/besu && sudo chown -R ${SSH_USER}:${SSH_USER} ${REMOTE_DIR}"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "$GENESIS" "${SSH_USER}@${EIP}:${REMOTE_DIR}/besu/genesis.json"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${NODE_DIR}/besu/entrypoint-besu.sh" "${SSH_USER}@${EIP}:${REMOTE_DIR}/besu/entrypoint-besu.sh"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${SCRIPT_DIR}/docker-compose.freetier.yml" "${SSH_USER}@${EIP}:${REMOTE_DIR}/docker-compose.yml"

# Empty placeholder: the bind mount must exist for Docker, and Besu's entrypoint waits for
# non-empty content before it will start. The real key is scp'd by ../aws/push-secrets.sh and
# is never written by git, never committed, and never baked into an AMI.
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "touch ${REMOTE_DIR}/besu/privatekey.txt && chmod 600 ${REMOTE_DIR}/besu/privatekey.txt"

echo "==> Pulling hyperledger/besu:26.10.0 (arm64) and starting the sealer"
# Plain `up -d`, same as ../aws/deploy.sh. besu-sealer declares
# `depends_on: besu-perms: condition: service_completed_successfully`, so compose runs the
# chown container and waits for it before Besu starts. The previous form here pre-created
# perms with `--no-start` and then started the sealer separately, which relies on compose
# re-starting an already-created dependency; if it did not, Besu would die with "Failed to
# create data directory: /var/lib/besu" (reproduced locally) while the instance billed.
# This compose file contains only those two services, so `up -d` brings up exactly them.
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "cd ${REMOTE_DIR} && docker compose pull && docker compose up -d"

# Same class of bug as preflight's: this line embedded `\$$$(python3 -c "…")` inside a heredoc.
# `\$` is a literal dollar, `$(` then opens a substitution whose inner quotes left an unbalanced
# `)"`, so bash aborted with "bad substitution: no closing `)'" AFTER the stack had already come up
# -- a deploy that had actually succeeded reported failure. Compute the number first, in quotes.
BURN_MO=$(python3 -c 'print(round(0.0089*730+0.005*730+1.5,1))')
BURN_LINE="~\$${BURN_MO}/mo"
[ "$INSTANCE_TYPE" = "t4g.micro" ] || BURN_LINE="(see preflight for $INSTANCE_TYPE)"

cat <<EOF

==> Provisioned.  Instance ${INSTANCE_ID}   EIP ${EIP}   burn ${BURN_LINE}

The chain will NOT seal yet: Besu is waiting for the validator key.

  1. Deliver the QBFT validator key (0xFaE699d2… is the only validator in this genesis):
       cd ../aws && ./push-secrets.sh
     Read the note in README.md about that key before you do -- this is the cheapest moment
     the project will ever get to rotate the consensus identity.

  2. Verify (block 0 must be 0x6c931dff…, then head must advance):
       ../aws-freetier/verify.sh ${EIP}

  3. DNS: rpc.lxon.in / explorer.lxon.in / www.lxon.in still point at 13.62.37.246, which is
     an EIP in the OLD account and can be reissued to a stranger by AWS. Move or delete those
     records before anything user-facing depends on them.
EOF
