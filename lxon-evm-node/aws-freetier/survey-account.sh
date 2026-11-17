#!/usr/bin/env bash
# What survived the terminated instance, and which region should the new node live in.
set -uo pipefail
P="${1:-lxon-remote}"

for r in us-east-1 eu-north-1; do
  echo "================= $r ================="
  printf '  instances : '
  aws ec2 describe-instances --profile "$P" --region "$r" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType]' --output text 2>&1 | tr '\n' '|'
  echo
  printf '  volumes   : '
  aws ec2 describe-volumes --profile "$P" --region "$r" \
    --query 'Volumes[].[VolumeId,State,Size,Encrypted]' --output text 2>&1 | tr '\n' '|'
  echo
  printf '  EIPs      : '
  aws ec2 describe-addresses --profile "$P" --region "$r" \
    --query 'Addresses[].[PublicIp,AllocationId]' --output text 2>&1 | tr '\n' '|'
  echo
  printf '  key pairs : '
  aws ec2 describe-key-pairs --profile "$P" --region "$r" --query 'KeyPairs[].KeyName' --output text 2>&1 | tr '\n' '|'
  echo
  printf '  SGs       : '
  aws ec2 describe-security-groups --profile "$P" --region "$r" \
    --query 'SecurityGroups[].GroupName' --output text 2>&1 | tr '\n' '|'
  echo
  printf '  t4g.micro offered here: '
  aws ec2 describe-instance-type-offerings --profile "$P" --region "$r" --location-type region \
    --filters 'Name=instance-type,Values=t4g.micro' \
    --query 'InstanceTypeOfferings[0].InstanceType' --output text 2>&1 | tr -d '\n'
  printf '   | t3.micro: '
  aws ec2 describe-instance-type-offerings --profile "$P" --region "$r" --location-type region \
    --filters 'Name=instance-type,Values=t3.micro' \
    --query 'InstanceTypeOfferings[0].InstanceType' --output text 2>&1 | tr -d '\n'
  echo
done

echo
echo "=== the terminated instance in detail ==="
aws ec2 describe-instances --profile "$P" --region us-east-1 \
  --instance-ids i-09ea5a833cbf52360 --output json 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
i=d["Reservations"][0]["Instances"][0]
print("  state          ", i["State"]["Name"], "(code %s)" % i["State"]["Code"])
print("  launched       ", i["LaunchTime"])
print("  type/arch      ", i["InstanceType"], i["Architecture"])
print("  ami            ", i["ImageId"])
print("  key name       ", i.get("KeyName"))
print("  IMDSv2 enforced", i["MetadataOptions"]["HttpTokens"], "(optional = IMDSv1 reachable)")
print("  tags           ", ", ".join(t["Key"] + "=" + t["Value"] for t in i.get("Tags", [])))
print("  iam profile    ", i.get("IamInstanceProfile","none attached"))
'
echo
echo "=== can this identity see its own credits / billable posture? ==="
printf '  budgets        : '
aws budgets describe-budgets --account-id 044409363656 --profile "$P" 2>&1 | head -1 | cut -c1-70
printf '  ce month costs : '
aws ce get-cost-and-usage --profile "$P" --time-period 2026-11-01/2026-11-30 \
  --metrics UnblendedCosts 2>&1 | head -1 | cut -c1-70
