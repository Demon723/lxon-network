#!/usr/bin/env bash
# Terminate the idle, unreachable us-east-1 instance chosen by the owner on 2026-11-03.
#
# Why a script instead of a hand-typed `aws ec2 terminate-instances`: the two IDs differ by a
# handful of hex characters (i-09ea5a833cbf52360 terminated, i-0c0426d9265615719 running) and a
# mistyped ID is either a no-op or, worse, a different resource. Everything here is re-read from
# AWS and asserted before the write. Irreversible -- a terminated instance cannot be restarted.
#
#   ./retire-idle-instance.sh            # dry run: show what would be destroyed
#   CONFIRM=yes ./retire-idle-instance.sh
set -uo pipefail

PROFILE="${PROFILE:-lxon-remote}"
EXPECTED_ACCOUNT="044409363656"
REGION="${REGION:-us-east-1}"
TARGET="${TARGET:-i-0c0426d9265615719}"
EXPECT_NAME_TAG="${EXPECT_NAME_TAG:-lxon-validator-1}"

echo "==> Retire $TARGET in $REGION (profile $PROFILE)"

ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>&1) || {
  echo "ERROR: cannot resolve identity: $ACCOUNT" >&2; exit 1; }
[ "$ACCOUNT" = "$EXPECTED_ACCOUNT" ] || {
  echo "ERROR: credentials are for account $ACCOUNT, not $EXPECTED_ACCOUNT." >&2; exit 1; }
echo "    account  : $ACCOUNT"

json=$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
         --instance-ids "$TARGET" --output json 2>&1) || {
  echo "ERROR: cannot describe $TARGET in $REGION: $(printf '%s' "$json" | head -1)" >&2; exit 1; }

read -r STATE TYPE NAME_TAG ROLE_TAG CHAIN_TAG VOL DOT PUBIP < <(printf '%s' "$json" | python3 -c '
import json,sys
i=json.load(sys.stdin)["Reservations"][0]["Instances"][0]
t={x["Key"]:x["Value"] for x in i.get("Tags",[])}
bds=i.get("BlockDeviceMappings") or []
# A terminated instance reports NO block device mappings at all, so indexing [0] raised
# IndexError and the script died before its own tag guard could explain why. Read it defensively
# so an already-dead instance produces a clean message instead of a traceback.
b = bds[0].get("Ebs",{}) if bds else {}
# The public address must be READ, not remembered: this instance has no EIP, so its public IP is
# ephemeral and changes on any stop/start. A hardcoded probe would test some other tenant host and
# report "no answer", letting a live chain be terminated on the strength of a stale literal.
ni=(i.get("NetworkInterfaces") or [{}])[0]
pub=ni.get("Association",{}).get("PublicIp","-")
print(i["State"]["Name"], i["InstanceType"], t.get("Name","-"), t.get("Role","-"),
      t.get("ChainId","-"), b.get("VolumeId","-"), str(b.get("DeleteOnTermination")), pub)
')
echo "    state    : $STATE"
echo "    type     : $TYPE"
echo "    tags     : Name=$NAME_TAG Role=$ROLE_TAG ChainId=$CHAIN_TAG"
echo "    volume   : $VOL  DeleteOnTermination=$DOT"
echo "    public ip: $PUBIP"

# Refuse unless this is unmistakably the box we mean.
[ "$NAME_TAG" = "$EXPECT_NAME_TAG" ] || {
  echo "ERROR: Name tag is '$NAME_TAG', expected '$EXPECT_NAME_TAG'. Wrong instance; aborting." >&2; exit 1; }
case "$STATE" in
  running|stopped|pending) : ;;
  *) echo "ERROR: state is '$STATE' (already terminated or unknown). Nothing to do." >&2; exit 1 ;;
esac

echo
echo "==> Will destroy:"
echo "    instance $TARGET  ($TYPE, $REGION)"
if [ "$DOT" = "True" ]; then
  echo "    volume   $VOL  -- deleted with it (DeleteOnTermination=$DOT)"
else
  echo "    volume   $VOL  -- SURVIVES termination and keeps billing \$0.05/GB-mo; delete it after"
fi
echo "    nothing else: this instance has no EIP and no IAM role attached."

# Is anything actually running on it? A box with a live chain must not be killed on a label.
printf '\n==> Liveness before destroying it\n'
if [ "$PUBIP" = "-" ]; then
  echo "    no public address; cannot probe. Confirm by other means that nothing is running."
else
  for p in 8545 8546 30303; do
    printf '    port %-5s on %s ' "$p" "$PUBIP"
    if curl -sS -m 4 -o /dev/null "http://$PUBIP:$p" 2>/dev/null; then
      echo "ANSWERING -- do NOT terminate until the chain on it is accounted for"; exit 1
    else
      echo "no answer"
    fi
  done
fi

if [ "${CONFIRM:-}" != "yes" ]; then
  echo
  echo "DRY RUN -- nothing was terminated. Re-run with CONFIRM=yes to proceed."
  exit 0
fi

echo
echo "==> Terminating $TARGET"
aws ec2 terminate-instances --profile "$PROFILE" --region "$REGION" --instance-ids "$TARGET" \
  --query 'TerminatingInstances[].[InstanceId,PreviousState.Name,CurrentState.Name]' --output text

# Post-state check: an irreversible write gets verified against what we expected, not assumed.
echo "==> waiting for terminal state"
if aws ec2 wait instance-terminated --profile "$PROFILE" --region "$REGION" --instance-ids "$TARGET"; then
  final=$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
            --instance-ids "$TARGET" --query 'Reservations[0].Instances[0].State.Name' --output text 2>&1)
  echo "    final state: $final"
  [ "$final" = "terminated" ] || { echo "ERROR: expected terminated, got $final" >&2; exit 1; }
else
  echo "ERROR: wait failed; re-check manually with ./find-instance.sh $PROFILE $TARGET" >&2
  exit 1
fi

if [ "$DOT" != "True" ] && [ "$VOL" != "-" ]; then
  echo
  echo "NOTE: volume $VOL was not set to delete on termination. Check it:"
  echo "  aws ec2 describe-volumes --profile $PROFILE --region $REGION --volume-ids $VOL"
  echo "If it is 'available' and untagged, it bills quietly forever. Delete it explicitly once"
  echo "you have confirmed nothing on it is needed (snapshot first if unsure)."
fi
echo "==> Done."
