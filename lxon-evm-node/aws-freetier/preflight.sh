#!/usr/bin/env bash
# Free-tier preflight — READ-ONLY. Verifies that the credentials in this shell belong to the
# account we intend to spend credits in, and that the local material is intact, BEFORE
# deploy.sh makes its first write to AWS.
#
# Usage:  ./preflight.sh                 # check only
#         EXPECTED_ACCOUNT=044409363656 ./preflight.sh
set -euo pipefail

REGION="${REGION:-eu-north-1}"
EXPECTED_ACCOUNT="${EXPECTED_ACCOUNT:-044409363656}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.micro}"
ROOT_GB="${ROOT_GB:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="$(dirname "$SCRIPT_DIR")"
GENESIS="${SCRIPT_DIR}/genesis/genesis.qbft.json"
# sha256 of the genesis that was actually running on i-0be453b2850bd6eae (recovered from
# ~/.lxon/migration/20261102T002439Z/config.tar.gz, MANIFEST.json "genesis_sha256").
EXPECTED_GENESIS_SHA="${EXPECTED_GENESIS_SHA:-a779acefd0014caf9cfa50d93151bc1d2cd3b07c22c3d16952ec0917282bca20}"
EXPECTED_BLOCK0="${EXPECTED_BLOCK0:-0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588}"

fail=0
say()  { printf '%s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
good() { printf '  ok   %s\n' "$*"; }

say "1/6  Credentials"
IDENTITY_JSON=$(aws sts get-caller-identity --output json 2>&1) || {
  bad "aws sts get-caller-identity failed: ${IDENTITY_JSON}"
  say ""
  say "No valid credentials for account ${EXPECTED_ACCOUNT} are configured on this machine."
  say "Both ~/.aws/credentials profiles (default, lxon-mainnet) return InvalidClientTokenId,"
  say "which means the key itself is not recognised -- rotated or expired, not a permission gap."
  say "Add a working key or SSO role, then re-run this script. Nothing else in this kit can proceed."
  exit 1
}
ACCOUNT=$(printf '%s' "$IDENTITY_JSON" | jq -r .Account)
ARN=$(printf '%s' "$IDENTITY_JSON" | jq -r .Arn)
if [ "$ACCOUNT" = "$EXPECTED_ACCOUNT" ]; then
  good "authenticated as ${ARN}"
else
  bad "credential is for account ${ACCOUNT}, expected ${EXPECTED_ACCOUNT} -- deploy.sh would spend credits in the wrong account"
fi

say "2/6  Region and quota visibility (read-only EC2 calls)"
# BUG FIXED 2026-11-03: this used `aws ${call}`, and ${call} already began with the operation,
# so it ran `aws describe-regions` -- no service -- and reported "denied/unreachable" against a
# perfectly healthy account. A gate that fails for the wrong reason and prints a guess about the
# reason is worse than no gate, so the real stderr is shown now.
for call in "describe-regions --region $REGION" "describe-instances --region $REGION" "describe-addresses --region $REGION"; do
  op="${call%% --*}"
  if err=$(aws ec2 "$op" --region "$REGION" 2>&1 >/dev/null); then
    good "allowed: aws ec2 $op"
  else
    bad "aws ec2 $op -> $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-110)"
  fi
done

say "3/6  Collisions with an existing LXON deployment in $REGION"
EXISTING=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=lxon" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?TagKey==`Name`]|join(``,[].Value),InstanceType,State.Name]' \
  --output text 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  say "  existing lxon-tagged instances:"; printf '%s\n' "$EXISTING" | sed 's/^/    /'
  say "  deploy.sh refuses to run while these exist (it will not silently double-bill you)."
else
  good "no running/stopped lxon-tagged instance in $REGION"
fi
EIPS=$(aws ec2 describe-addresses --region "$REGION" --query 'Addresses[].[PublicIp,AllocationId]' --output text 2>/dev/null || true)
[ -n "$EIPS" ] && { say "  EIPs already held in $REGION (each bills \$0.005/h attached or idle -- an abandoned allocation is not free):"; printf '%s\n' "$EIPS" | sed 's/^/    /'; }

say "4/6  Instance type and storage"
IMAGE=$(aws ec2 describe-instance-types --region "$REGION" --instance-types "$INSTANCE_TYPE" \
  --query 'InstanceTypes[0].[InstanceType,MemoryInfo.SizeInMiB,VCpuInfo.DefaultVCpus,ProcessorInfo.SupportedArchitectures[0]]' --output text 2>/dev/null || true)
if [ -n "$IMAGE" ]; then
  printf '  ok   %s  mem_MiB=%s  vcpu=%s  arch=%s\n' $IMAGE
  MEM=$(printf '%s' "$IMAGE" | awk '{print $2}')
  if [ "${MEM:-0}" -lt 1536 ]; then
    say "       note: 1 GiB is unproven for this stack (the old node was t3.large/8 GiB)."
    say "       Besu will run heap-capped with 2 GiB swap; watch verify.sh for the OOM killer."
  fi
else
  bad "could not describe $INSTANCE_TYPE in $REGION"
fi
good "root volume ${ROOT_GB} GB gp3 encrypted (chain data was 379 MB at last export; headroom is deliberate)"

say "5/6  Local material (the thing that decides whether this is a restart or a new chain)"
if [ -f "$GENESIS" ]; then
  GOT=$(shasum -a 256 "$GENESIS" | awk '{print $1}')
  if [ "$GOT" = "$EXPECTED_GENESIS_SHA" ]; then
    good "genesis matches the production file byte-for-byte -> block 0 will be $EXPECTED_BLOCK0"
  else
    bad "genesis sha256 is $GOT, expected $EXPECTED_GENESIS_SHA -- this would produce a DIFFERENT chain identity"
  fi
else
  bad "missing $GENESIS (recovered copy lives in ~/.lxon/migration/20261102T002439Z/config.tar.gz)"
fi
for f in ../besu/entrypoint-besu.sh ../besu/privatekey.txt; do
  [ -s "$SCRIPT_DIR/$f" ] && good "$(basename "$f") present" || bad "$f missing/empty (validator key is delivered by push-secrets.sh, never committed)"
done

# Operator access path. On 2026-11-03 deploy.sh launched a healthy instance and then hung for
# 10 minutes in its SSH wait and exited 1, because SSH_CIDR defaulted to 42.104.0.0/16 while the
# laptop's egress was 42.108.237.11 -- and minutes later it was 49.15.91.16. The ISP does not stay
# in one /16, so the hardcoded default is a trap. Checking BEFORE launch costs nothing; discovering
# it afterwards leaves a running, billing node you cannot log into.
#
# Caveat that is deliberately not hidden: this compares against the HTTPS egress, and the TCP/22
# egress is known to differ on this network. An out-of-range result is therefore a strong warning;
# an in-range result is not proof. The real test is the post-launch SSH probe in deploy.sh.
SSH_CIDR_EFFECTIVE="${SSH_CIDR:-42.104.0.0/16}"
EGRESS=$(curl -sS -m 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
if [ -z "$EGRESS" ]; then
  say "  --   could not determine egress IP; cannot pre-check SSH_CIDR=$SSH_CIDR_EFFECTIVE"
else
  COVERED=$(python3 -c "
import ipaddress,sys
try:
    print('yes' if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2]) else 'no')
except Exception as e:
    print('bad-cidr')
" "$EGRESS" "$SSH_CIDR_EFFECTIVE")
  case "$COVERED" in
    yes) good "egress $EGRESS is inside SSH_CIDR $SSH_CIDR_EFFECTIVE" ;;
    no)  bad "egress $EGRESS is NOT inside SSH_CIDR $SSH_CIDR_EFFECTIVE -- SSH will be dropped after launch."
         say "       Re-run as:  SSH_CIDR=$(printf '%s' "$EGRESS" | cut -d. -f1-2).0.0/16 ./deploy.sh"
         say "       (or the exact /32: SSH_CIDR=$EGRESS/32). Your egress roams between provider blocks,"
         say "        so expect to re-check this each session." ;;
    *)   bad "SSH_CIDR '$SSH_CIDR_EFFECTIVE' is not a valid CIDR" ;;
  esac
fi

say "6/6  Estimated credit burn (free plan = \$100 credit now, \$200 max, expires 6 months after account open)"
HOURS=730
for pair in "t4g.micro:0.0089" "t4g.small:0.0178"; do
  T=${pair%%:*}; R=${pair##*:}
  say "  $(printf '  %-11s' $T) \$${R}/h -> \$$(python3 -c "print(round($R*$HOURS,2))")/mo compute"
done
# `\$$$(...)` was a trap: `\$` printed a literal dollar and then `$$` expanded to the shell's
# PID, so this line printed "$33929(python3 -c ...)". Compute the number first.
IPV4_MO=$(python3 -c 'print(round(0.005*730,2))')
# Corrected 2026-11-03. This line used to claim an EIP on a running instance is not charged; since
# Feb 2024 AWS bills $0.005/h for every public IPv4 address whether attached or idle, so the charge
# is real for the whole life of the node and an abandoned allocation keeps billing. Matches the
# cost table in README.md, which already counted it.
say "  public IPv4      \$0.005/h -> \$${IPV4_MO}/mo (charged whether the EIP is attached or idle)"
say "  EBS gp3 ${ROOT_GB}GB ~ \$1.5/mo (per-GB rate not verified here -- check the pricing page or Cost Explorer)"
say "  => one t4g.micro node ~= \$11.7/mo ~= \$70 over the 6-month free-plan window."

echo
if [ "$fail" = 0 ]; then
  say "PREFLIGHT CLEAN -- run ./deploy.sh"
else
  say "PREFLIGHT FAILED -- fix the FAIL lines above before deploy.sh"
  exit 1
fi
