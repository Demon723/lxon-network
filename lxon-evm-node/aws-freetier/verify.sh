#!/usr/bin/env bash
# Post-deploy verification for the free-tier 724 node. Read-only against the instance.
#
#   ./verify.sh                 # resolves the EIP from the AWS tag
#   ./verify.sh 1.2.3.4         # or pass it
#
# Every check is answered by the running system, not by a remembered value: block 0 hash,
# sealing progress, JVM heap cap actually on the process line, and whether the OOM killer
# has already taken Besu.
set -uo pipefail

REGION="${REGION:-eu-north-1}"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SSH_USER="ubuntu"
EXPECTED_BLOCK0="${EXPECTED_BLOCK0:-0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588}"
EXPECTED_CHAINID="${EXPECTED_CHAINID:-0x2d4}"

EIP="${1:-}"
if [ -z "$EIP" ]; then
  EIP=$(aws ec2 describe-addresses --region "$REGION" \
    --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text 2>/dev/null)
fi
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: no EIP; pass it as \$1" >&2; exit 2; }
[ -f "$KEY_FILE" ] || { echo "ERROR: $KEY_FILE missing" >&2; exit 2; }

rpc() {  # $1 = method, $2 = params json
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${SSH_USER}@${EIP}" \
    "curl -sS -m 8 -X POST -H 'content-type: application/json' --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}' http://127.0.0.1:8545"
}

pass=0; failed=0
chk() { # $1 label, $2 got, $3 want
  if [ "$2" = "$3" ]; then printf '  ok   %-26s %s\n' "$1" "$2"; pass=$((pass+1));
  else printf '  FAIL %-26s got=%s want=%s\n' "$1" "$2" "$3"; failed=$((failed+1)); fi
}
info() { printf  '  --   %-26s %s\n' "$1" "$2"; }

echo "==> ${EIP}  (chain 724, free-tier)"

STATE=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-ft" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
chk instance-state "$STATE" "running"

DOCKER=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "docker ps --filter name=lxon-besu-sealer --format '{{.Names}} {{.Status}}' 2>&1" 2>/dev/null)
case "$DOCKER" in *healthy*) chk container "healthy" "healthy";; *) chk container "$DOCKER" "healthy";; esac

HEAP=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "docker exec lxon-besu-sealer sh -c 'ps -ef | grep -o \"\-Xmx[0-9]*m\" | head -1' 2>&1" 2>/dev/null)
chk jvm-heap-cap "${HEAP:--Xmxnone}" "-Xmx512m"

MEM=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "free -m | awk '/^Mem/{print \$3\"/\"\$2\"MB\"}; /^Swap/{if (\$3>0) s=\"swap_used_\"\$3\"MB\"} END{print (s!=\"\"?s:\"swap_idle\")}'" 2>/dev/null)
info rss-and-swap "$MEM"

OOM=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "sudo dmesg 2>/dev/null | grep -ci 'Out of memory' || true" 2>/dev/null)
chk oom-killer-events "${OOM:-0}" "0"

CID=$(rpc eth_chainId '[]' | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
chk chain-id "${CID:-none}" "$EXPECTED_CHAINID"

B0=$(rpc eth_getBlockByNumber '["0x0",false]' | sed -n 's/.*"hash":"\([^"]*\)".*/\1/p')
chk block0-hash "${B0:-none}" "$EXPECTED_BLOCK0"

H1=$(rpc eth_blockNumber '[]' | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
sleep 14
H2=$(rpc eth_blockNumber '[]' | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
if [ -n "$H1" ] && [ -n "$H2" ] && [ "$H1" != "$H2" ]; then
  printf '  ok   %-26s %s -> %s (sealing)\n' "head-advancing" "$H1" "$H2"; pass=$((pass+1))
elif [ -z "$H2" ]; then
  printf '  FAIL %-26s no RPC answer -- is the validator key delivered (push-secrets.sh)?\n' "head-advancing"; failed=$((failed+1))
else
  printf '  FAIL %-26s %s == %s, frozen. Besu waits for /key/key.priv until it is non-empty.\n' "head-advancing" "$H1" "$H2"; failed=$((failed+1))
fi

PEERS=$(rpc net_peerCount '[]' | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
info peer-count "${PEERS:-none}  (0 is expected for a solo chain with no second node)"

DISK=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "df -h / | awk 'NR==2{print \$5\" used of \"\$2}'" 2>/dev/null)
info root-disk "$DISK"

LOG=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "docker logs --tail 6 lxon-besu-sealer 2>&1 | tail -3" 2>/dev/null)
info last-log "$(printf '%s' "$LOG" | tr '\n' ' ' | cut -c1-110)"

echo
echo "==> ${pass} checks passed, ${failed} failed"
[ "$failed" -eq 0 ] || exit 1
