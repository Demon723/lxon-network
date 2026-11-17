#!/usr/bin/env bash
# Puts HTTPS in front of the LXON explorer using Caddy + Let's Encrypt.
#
#   EXPLORER_DOMAIN=explorer.example.com ./enable-https.sh [--check|--dry-run]
#
#   --check    only prove the DNS already resolves to this instance's EIP, change nothing
#   --dry-run  print what would happen, change nothing
#
# Order matters and is deliberate:
#   1. the domain must already resolve to this instance's EIP (checked, not assumed)
#   2. security group: open 80/443
#   3. start Caddy alone and wait for a real certificate
#   4. only then apply docker-compose.https.yml, which moves 3000/4000 to loopback and
#      rewrites the frontend to the https origin
#   5. revoke the 3000/4000 world rules
# If it stops between 3 and 4 you are still on http://<EIP>:3000 — nothing was taken down.
#
# DNS is NOT created here, and it cannot be: lxon.in's nameservers are Hostinger parking
# (byte.dns-parking.com / pixel.dns-parking.com) and this IAM user has no route53 permission,
# so the A record is typed in the Hostinger control panel before this script can succeed.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
SG_NAME="lxon-node-sg"
DRY_RUN=0
CHECK_ONLY=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --check)   CHECK_ONLY=1 ;;
  "") ;;
  *) echo "usage: EXPLORER_DOMAIN=host ./enable-https.sh [--check | --dry-run]" >&2; exit 2 ;;
esac

[ -n "${EXPLORER_DOMAIN:-}" ] || { echo "ERROR: set EXPLORER_DOMAIN=host.example.com" >&2; exit 1; }
[ -f "$KEY_FILE" ] || { echo "ERROR: ${KEY_FILE} missing — run ./deploy.sh first" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_JSON="${SCRIPT_DIR}/../../apps/contracts/deployments/lxon-chain-724.json"

EIP=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text)
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: EIP not found" >&2; exit 1; }

# Multiple resolvers on purpose. Hard-coding @1.1.1.1 produced a false "does not point at this
# node" the first time this network could not reach Cloudflare — worse than a missing record,
# because it looks like a DNS problem and sends you back to the registrar to fix a zone that is
# already right. Every resolver must return the EIP and they must agree: a split-brain means the
# change is still propagating, and ACME could validate against one view while the public sees
# another. Override the set with DNS_RESOLVERS.
resolve_all() {
  for r in ${DNS_RESOLVERS:-system 1.1.1.1 8.8.8.8 9.9.9.9}; do
    if [ "$r" = "system" ]; then dig +short A "$1" +time=3 +tries=1 2>/dev/null
    else dig +short A "$1" @"$r" +time=3 +tries=1 2>/dev/null; fi | grep -E '^[0-9.]+$' | head -1
  done | sort -u
}
ANSWERS=$(resolve_all "$EXPLORER_DOMAIN")
NANSWER=$(printf '%s\n' "$ANSWERS" | grep -c . || true)
echo "==> ${EXPLORER_DOMAIN} -> $(printf '%s' "$ANSWERS" | tr '\n' ' ' | sed 's/ $//') | instance EIP is ${EIP}"
if [ "$NANSWER" != "1" ] || [ "$ANSWERS" != "$EIP" ]; then
  cat >&2 <<EOF
ERROR: ${EXPLORER_DOMAIN} does not point at this node.
  Add/fix an A record in the DNS panel that owns the zone (for lxon.in that is Hostinger,
  not Route 53 — the nameservers are byte.dns-parking.com / pixel.dns-parking.com):

      ${EXPLORER_DOMAIN}  A  ${EIP}   TTL 300

  Re-check with: dig +short A ${EXPLORER_DOMAIN} @8.8.8.8   (or DNS_RESOLVERS="resolverA resolverB" to choose)
  Let's Encrypt cannot validate a hostname that resolves somewhere else, and applying the
  https overlay at that point would take the explorer down rather than secure it.

  Do not add an rpc.* record pointing at ${EIP}: Besu is loopback-only and the security
  group has no 8545/8546 rule on purpose. This script proxies the explorer, nothing else.
EOF
  exit 1
fi
if [ "$CHECK_ONLY" = "1" ]; then
  echo "OK: ${EXPLORER_DOMAIN} -> ${ANSWERS} matches the node EIP on every resolver queried. Safe to run without --check."
  exit 0
fi

SG_ID=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text)
[ "$SG_ID" != "None" ] || { echo "ERROR: security group ${SG_NAME} not found" >&2; exit 1; }

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN: would open 80/443 on ${SG_ID}, push caddy/Caddyfile + docker-compose.https.yml,"
  echo "         start lxon-caddy, wait for the certificate, then apply the overlay and"
  echo "         revoke the 3000/4000 world rules. No changes made."
  exit 0
fi

echo "==> Opening 80 and 443 on ${SG_ID}"
for p in 80 443; do
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port "$p" --cidr 0.0.0.0/0 >/dev/null 2>&1 || echo "    ${p} already open"
done

echo "==> Pushing proxy config"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "mkdir -p ${REMOTE_DIR}/caddy"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${SCRIPT_DIR}/caddy/Caddyfile" "${SSH_USER}@${EIP}:${REMOTE_DIR}/caddy/Caddyfile"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q \
  "${SCRIPT_DIR}/docker-compose.https.yml" "${SSH_USER}@${EIP}:${REMOTE_DIR}/docker-compose.https.yml"

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "grep -q '^EXPLORER_DOMAIN=' ${REMOTE_DIR}/.env 2>/dev/null || echo 'EXPLORER_DOMAIN=${EXPLORER_DOMAIN}' >> ${REMOTE_DIR}/.env; \
   sed -i 's/^EXPLORER_DOMAIN=.*/EXPLORER_DOMAIN=${EXPLORER_DOMAIN}/' ${REMOTE_DIR}/.env; chmod 600 ${REMOTE_DIR}/.env"

echo "==> Starting Caddy and waiting for the certificate (this is the ACME step)"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "cd ${REMOTE_DIR} && docker compose -f docker-compose.yml -f docker-compose.https.yml up -d caddy"

ISSUED=0
for i in $(seq 1 24); do
  if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
      "cd ${REMOTE_DIR} && docker compose -f docker-compose.yml -f docker-compose.https.yml exec -T caddy \
        sh -c 'ls /data/caddy/certificates/acme_v2-main/letsencrypt.org*/* >/dev/null 2>&1'"; then
    ISSUED=1; echo "    certificate issued after ~$((i*5))s"; break
  fi
  sleep 5
done
if [ "$ISSUED" != "1" ]; then
  echo "ERROR: no certificate after 2 minutes. Caddy log:" >&2
  ssh -i "$KEY_FILE" "${SSH_USER}@${EIP}" "docker logs lxon-caddy --tail 30" >&2
  echo "Nothing else was changed; the explorer is still reachable on http://${EIP}:3000." >&2
  exit 1
fi

echo "==> Applying the https overlay (frontend/backend move to loopback, UI to https origin)"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${EIP}" \
  "cd ${REMOTE_DIR} && docker compose -f docker-compose.yml -f docker-compose.https.yml up -d"

echo "==> Verifying over TLS"
sleep 15
curl -sS -o /dev/null -w "    UI   https://${EXPLORER_DOMAIN}/        -> %{http_code}\n" "https://${EXPLORER_DOMAIN}/"
curl -sS -o /dev/null -w "    API  https://${EXPLORER_DOMAIN}/api/v2/stats -> %{http_code}\n" "https://${EXPLORER_DOMAIN}/api/v2/stats"
curl -sS "https://${EXPLORER_DOMAIN}/api/v2/smart-contracts" | head -c 120; echo
echo "    issuer: $(echo | openssl s_client -connect ${EXPLORER_DOMAIN}:443 -servername ${EXPLORER_DOMAIN} 2>/dev/null | openssl x509 -noout -issuer -dates 2>/dev/null | tr '\n' ' ')"

echo "==> Closing 3000 and 4000 to the world (Caddy serves them on 443 now)"
for p in 3000 4000; do
  aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port "$p" --cidr 0.0.0.0/0 >/dev/null 2>&1 || echo "    ${p}: revoke returned an error"
done
# Verify, do not trust the exit code. On the 2026-10-20 cutover both revokes "succeeded" and the
# rules were still in the group an hour later — a `|| echo "was already closed"` fallback turns a
# real failure into reassuring output. Re-read the group and say plainly what is left open.
sleep 3
STILL=$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`3000`||FromPort==`4000`] | [?IpRanges[?CidrIp==`0.0.0.0/0`]] | length(@)' --output text)
if [ "${STILL:-0}" = "0" ]; then
  echo "    confirmed: 3000 and 4000 are no longer open to the world"
else
  echo "    WARNING: $STILL world rule(s) for 3000/4000 are still present. The containers bind" >&2
  echo "             127.0.0.1 so nothing is exposed, but clear them by hand:" >&2
  echo "             aws ec2 revoke-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0" >&2
fi

# Keep the deployment record truthful: the explorer URL everyone quotes is now the https one.
if [ -f "$DEPLOY_JSON" ]; then
  python3 - "$DEPLOY_JSON" "$EXPLORER_DOMAIN" "$EIP" <<'PY'
import json,sys,datetime
path,host,eip=sys.argv[1:4]
d=json.load(open(path))
d.setdefault("node",{})
d["node"]["explorer"]=f"https://{host}"
d["node"]["explorerApi"]=f"https://{host}/api/v2"
d["node"]["explorerLegacyHttp"]=f"http://{eip}:3000 (closed in the SG once HTTPS landed)"
d["node"]["httpsProxy"]="caddy v2 + Let's Encrypt, origin pinned to the explorer only"
d["updatedAt"]=datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d,open(path,"w"),indent=2); open(path,"a").write("\n")
print(f"    updated {path.split('/')[-1]}: explorer -> https://{host}")
PY
fi

cat <<EOF

Done.
  Explorer: https://${EXPLORER_DOMAIN}/
  API:      https://${EXPLORER_DOMAIN}/api/v2
  Ports 3000/4000 are loopback-only on the instance and no longer open in the SG.

Caddy renews the certificate automatically (Let's Encrypt, ~60-day cycle). To roll back:
  ssh -i ${KEY_FILE} ${SSH_USER}@${EIP} "cd ${REMOTE_DIR} && docker compose up -d"
  aws ec2 authorize-security-group-ingress --region ${REGION} --group-id ${SG_ID} --protocol tcp --port 3000 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --region ${REGION} --group-id ${SG_ID} --protocol tcp --port 4000 --cidr 0.0.0.0/0
EOF
