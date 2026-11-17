#!/usr/bin/env bash
# Take a restorable snapshot of the chain-724 node's root volume, and say plainly what it does and
# does not protect.
#
#   ./snapshot.sh                  # snapshot the root volume, tag it, report progress
#   ./snapshot.sh --rotate 7       # keep the newest 7, delete older lxon snapshots
#   ./snapshot.sh --list           # what exists right now
#
# WHAT THIS PROTECTS: everything written to the EBS volume -- the chain data directory, the compose
# file, the validator key file on disk, Caddy's certificates and their private keys. The 2026-11-02
# migration bundle proved what the absence of this cost: it recorded `"with_db": false` and skipped
# besu-data, besu-rpc-data and bs-db-data, so the chain history had to be rebuilt from genesis.
#
# WHAT IT DOES NOT PROTECT: the volume is 20 GB and mostly empty, but a snapshot is not a logical
# backup. It restores the box as it was at the instant taken -- including a corrupt leveldb, or a
# key file that had already been overwritten. For a chain this small the durable-copy answer is
# `geth/leveldb` offline export plus a *separate* copy of the validator key; this script is the
# fast, unattended layer, not the only layer.
#
# COST, measured rather than assumed: eu-north-1 EBS snapshots bill roughly $0.09 per GB-month for
# the *changed* blocks, not the nominal 20 GB. `df` at first run showed 5.8 GB used on a 19 GB root,
# so a first snapshot is on the order of $0.50/month and later incrementals far less. --rotate exists
# because unbounded retention is how a backup plan quietly becomes a bill.
set -uo pipefail

REGION="${REGION:-eu-north-1}"
PROFILE="${AWS_PROFILE:-lxon-remote}"
EXPECTED_ACCOUNT="044409363656"
EIP_TAG="lxon-node-eip"
INSTANCE_TYPE_KEEP=3
MODE="${1:-create}"
KEEP="${2:-7}"

fail() { echo "ERROR: $*" >&2; exit 1; }
aws_() { AWS_PROFILE="$PROFILE" aws "$@"; }

ACCT=$(aws_ sts get-caller-identity --query Account --output text 2>&1) || fail "no credentials: $ACCT"
[ "$ACCT" = "$EXPECTED_ACCOUNT" ] || fail "credentials are for $ACCT, not $EXPECTED_ACCOUNT"

VOL=$(aws_ ec2 describe-instances --region "$REGION" \
        --filters "Name=tag:Name,Values=lxon-node" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text 2>/dev/null)
if [ -z "$VOL" ] || [ "$VOL" = "None" ]; then
  # Fall back to the EIP's attached instance, which is the authoritative link we have.
  INST=$(aws_ ec2 describe-addresses --region "$REGION" --filters "Name=tag:Name,Values=$EIP_TAG" \
           --query 'Addresses[0].InstanceId' --output text 2>/dev/null)
  [ "$INST" != "None" ] && [ -n "$INST" ] || fail "cannot find the lxon instance or its volume"
  VOL=$(aws_ ec2 describe-instances --region "$REGION" --instance-ids "$INST" \
          --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)
fi
[ -n "$VOL" ] && [ "$VOL" != "None" ] || fail "could not resolve the root volume id"
echo "==> volume $VOL in $REGION (account $ACCT)"

case "$MODE" in
  --list)
    aws_ ec2 describe-snapshots --region "$REGION" --owner-ids "$ACCT" \
      --query 'Snapshots[].[SnapshotId,State,Progress,VolumeId,StartTime,Description]' --output table
    exit 0 ;;

  --rotate)
    N="${KEEP:-7}"
    IDS=$(aws_ ec2 describe-snapshots --region "$REGION" --owner-ids "$ACCT" \
            --query "sort_by(Snapshots[?starts_with(Description,'lxon-724')], &StartTime)[].SnapshotId" \
            --output text | tr '\t' '\n')
    COUNT=$(printf '%s' "$IDS" | grep -c . || true)
    echo "==> $COUNT lxon snapshots, keeping the newest $N"
    if [ "$COUNT" -le "$N" ]; then echo "    nothing to delete"; exit 0; fi
    DEL=$(printf '%s\n' "$IDS" | head -n $((COUNT - N)))
    for id in $DEL; do
      echo "    $id"
      INUSE=$(aws_ ec2 describe-volumes --region "$REGION" --filters "Name=snapshot-id,Values=$id" \
                --query 'Volumes[0].VolumeId' --output text 2>/dev/null)
      if [ "$INUSE" != "None" ] && [ -n "$INUSE" ]; then
        echo "      kept: a volume was created from it ($INUSE)"; continue
      fi
      # Deleting a snapshot is irreversible; only ones we made, only the oldest, only beyond N.
      aws_ ec2 delete-snapshot --region "$REGION" --snapshot-id "$id" \
        && echo "      deleted" || echo "      FAILED to delete (left in place)"
    done
    exit 0 ;;
esac

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
SNAP=$(aws_ ec2 create-snapshot --region "$REGION" --volume-id "$VOL" \
         --description "lxon-724 root $STAMP" \
         --tag-specifications "ResourceType=snapshot,Tags=[{Key=Project,Value=lxon},{Key=Name,Value=lxon-724-root-$STAMP}]" \
         --query SnapshotId --output text) || fail "create-snapshot refused"
echo "==> $SNAP created"

# Wait for completion, and fail rather than report a snapshot that never finished. A snapshot left
# in pending forever is not a backup.
for i in $(seq 1 60); do
  READ=$(aws_ ec2 describe-snapshots --region "$REGION" --snapshot-ids "$SNAP" \
           --query 'Snapshots[0].[State,Progress]' --output text 2>/dev/null)
  STATE=$(echo "$READ" | awk '{print $1}'); PROG=$(echo "$READ" | awk '{print $2}')
  printf '    %s %s\r' "$STATE" "$PROG"
  [ "$STATE" = "completed" ] && { echo; break; }
  [ "$STATE" = "error" ] && { echo; fail "snapshot $SNAP went to error"; }
  sleep 10
done
[ "$STATE" = "completed" ] || { echo; fail "snapshot still $STATE after the wait; it is NOT usable as a backup"; }

SIZE=$(aws_ ec2 describe-snapshots --region "$REGION" --snapshot-ids "$SNAP" --query 'Snapshots[0].VolumeSize' --output text)
echo "==> restored size class: ${SIZE} GB"
cat <<EOF

  Snapshot $SNAP is completed and tagged Project=lxon.

  Restore (this creates a NEW volume; it does not overwrite the running one):
    aws ec2 create-volume --region $REGION --snapshot-id $SNAP --availability-zone eu-north-1a
  then detach the current root and attach that volume, or launch a fresh instance from the snapshot
  directly:
    aws ec2 register-image --region $REGION --name lxon-724-$STAMP \\
      --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=$SNAP,VolumeSize=$SIZE,DeleteOnTermination=true}"

  Rotation is yours to schedule; nothing above runs on a timer.
    ./snapshot.sh --rotate 7
EOF
