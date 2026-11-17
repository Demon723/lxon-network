#!/usr/bin/env bash
# Publishes a read-only public JSON-RPC endpoint for chain 724 on https://<RPC_DOMAIN>.
#
#   RPC_DOMAIN=rpc.lxon.in ./enable-public-rpc.sh [--check|--dry-run]
#
#   --check    only prove RPC_DOMAIN resolves to this instance's EIP; change nothing
#   --dry-run  print the plan; change nothing
#
# Prerequisite: ./enable-https.sh has already run, because this overlay mounts into the
# caddy service defined by docker-compose.https.yml.
#
# The design point worth keeping in mind: this never opens the sealer's port. A second
# Besu full node (docker-compose.rpc.yml) is what faces the internet, and it carries no
# validator key and no QBFT/ADMIN/MINER/DEBUG/TXPOOL/TRACE namespaces. On a 1-validator
# QBFT chain a reachable qbft_proposeValidatorVote is a chain takeover, so the guarantee
# has to come from the namespaces not being loaded, not from a firewall rule.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
KEY_FILE="$HOME/.ssh/lxon-${REGION}.pem"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
NET="lxon-evm_default"
SG_NAME="lxon-node-sg"
DRY_RUN=0; CHECK_ONLY=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --check)   CHECK_ONLY=1 ;;
  "") ;;
  *) echo "usage: RPC_DOMAIN=host ./enable-public-rpc.sh [--check | --dry-run]" >&2; exit 2 ;;
esac

[ -n "${RPC_DOMAIN:-}" ] || { echo "ERROR: set RPC_DOMAIN=host.example.com" >&2; exit 1; }
[ -f "$KEY_FILE" ] || { echo "ERROR: ${KEY_FILE} missing — run ./deploy.sh first" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_JSON="${SCRIPT_DIR}/../../apps/contracts/deployments/lxon-chain-724.json"

EIP=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text)
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: EIP not found" >&2; exit 1; }
SSH=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "${SSH_USER}@${EIP}")
# NOTE: deploy.sh pushes local aws/docker-compose.aws.yml to the node AS /opt/lxon/docker-compose.yml,
# so there is no docker-compose.aws.yml on the instance — reference the three files that are.
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.https.yml -f docker-compose.rpc.yml"

q()  { "${SSH[@]}" "$@"; }                    # run a command on the node
rq() { q "${REMOTE_DIR}/bin/rpcq.sh" "$@" 2>/dev/null || true; }   # JSON-RPC from inside the network
jq_result() { python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("result"))
except Exception: print(None)'; }

# Same rule as enable-https.sh (duplicated so each script stays standalone): query several
# resolvers and require one answer, equal to the EIP. A single hard-coded @1.1.1.1 gives a false
# "does not point at this node" whenever this network cannot reach Cloudflare, and split-brain
# answers mean the record is still propagating while ACME sees a different world than users do.
resolve_all() {
  for r in ${DNS_RESOLVERS:-system 1.1.1.1 8.8.8.8 9.9.9.9}; do
    if [ "$r" = "system" ]; then dig +short A "$1" +time=3 +tries=1 2>/dev/null
    else dig +short A "$1" @"$r" +time=3 +tries=1 2>/dev/null; fi | grep -E '^[0-9.]+$' | head -1
  done | sort -u
}
ANSWERS=$(resolve_all "$RPC_DOMAIN")
NANSWER=$(printf '%s\n' "$ANSWERS" | grep -c . || true)
echo "==> ${RPC_DOMAIN} -> $(printf '%s' "$ANSWERS" | tr '\n' ' ' | sed 's/ $//') | instance EIP is ${EIP}"
if [ "$NANSWER" != "1" ] || [ "$ANSWERS" != "$EIP" ]; then
  cat >&2 <<EOF
ERROR: ${RPC_DOMAIN} does not point at this node on every resolver queried.
  Add the A record where the zone is actually served (lxon.in uses Hostinger parking
  nameservers, byte.dns-parking.com / pixel.dns-parking.com — not Route 53):

      ${RPC_DOMAIN}  A  ${EIP}   TTL 300

  Let's Encrypt cannot validate a host that resolves elsewhere. Refusing here is the whole
  point: the node and the certificate are independent steps, and a half-done cutover would
  leave an rpc.* name published against a port nobody answers.
EOF
  exit 1
fi
if [ "$CHECK_ONLY" = "1" ]; then echo "OK: ${RPC_DOMAIN} -> ${ANSWERS} on every resolver. Safe to run without --check."; exit 0; fi

# Hard prerequisite, not a nicety: docker-compose.rpc.yml merges into the caddy service that
# only exists in docker-compose.https.yml, so compose refuses to interpolate the project at
# all without EXPLORER_DOMAIN. Fail here with the reason instead of at the recreate step.
# No nested quotes in this pattern on purpose: `\'...\'` through ssh hands the remote shell a
# literal apostrophe inside the regex, so the check fails even when the variable IS set — which
# is exactly what happened on the first run of this script.
if ! "${SSH[@]}" "grep -qE ^EXPLORER_DOMAIN=. ${REMOTE_DIR}/.env" 2>/dev/null; then
  echo "ERROR: ${REMOTE_DIR}/.env has no EXPLORER_DOMAIN — run ./enable-https.sh first." >&2
  echo "       This overlay extends the caddy service defined by docker-compose.https.yml; without it" >&2
  echo "       docker compose cannot even resolve the project." >&2
  exit 1
fi

echo "==> Reading the sealer's head from inside the compose network"
"${SSH[@]}" "test -x ${REMOTE_DIR}/bin/rpcq.sh" 2>/dev/null || {
  q "mkdir -p ${REMOTE_DIR}/bin"
  scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/rpcq.sh" "${SSH_USER}@${EIP}:${REMOTE_DIR}/bin/rpcq.sh"
  q "chmod 700 ${REMOTE_DIR}/bin/rpcq.sh"
}
SEALER_HEAD=$(rq http://besu-sealer:8545 eth_blockNumber | jq_result)
[ -n "$SEALER_HEAD" ] && [ "$SEALER_HEAD" != "None" ] || {
  echo "ERROR: cannot reach besu-sealer:8545 — is the stack running?" >&2; exit 1; }
SEALER_HEAD=$(( SEALER_HEAD ))
echo "    sealer head: ${SEALER_HEAD}"

ENODE=$(q "docker logs lxon-besu-sealer 2>&1 | grep -m1 -oE 'enode://[0-9a-f]{128}'")
SEALER_IP=$(q "docker inspect lxon-besu-sealer --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'")
[ -n "$ENODE" ] || { echo "ERROR: no enode in the sealer log — is lxon-besu-sealer the right container?" >&2; exit 1; }
LXON_SEALER_ENODE="${ENODE}@${SEALER_IP}:30303"
echo "    bootnode:    enode://${ENODE:0:16}…@${SEALER_IP}:30303"

if [ "$DRY_RUN" = "1" ]; then
  cat <<EOF
DRY RUN — would, in order:
  1. ensure 80/443 are open in ${SG_NAME} (8545/8546 stay closed)
  2. push docker-compose.rpc.yml + caddy/rpc-site.caddy -> ${REMOTE_DIR}/caddy/sites-enabled/02-rpc.caddy
  3. write RPC_DOMAIN / RPC_PUBLIC_URL / LXON_SEALER_ENODE into ${REMOTE_DIR}/.env (chmod 600)
  4. start besu-rpc only, wait until eth_syncing == false AND head >= ${SEALER_HEAD}
  5. caddy validate the combined config BEFORE reloading — a bad Caddyfile would take the
     explorer's TLS down too, so a failure here deletes the rpc site and stops
  6. recreate caddy + blockscout-backend, wait for the certificate on ${RPC_DOMAIN}
  7. verify over TLS: eth_chainId, head, and that qbft_/admin_/debug_/trace_/txpool_ all
     answer 'Method not enabled' — namespaces absent, not filtered
  8. record https://${RPC_DOMAIN} in the deployment JSON and print the rollback
Nothing was changed.
EOF
  exit 0
fi

SG_ID=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text)
echo "==> Ensuring 80/443 are open (8545/8546 deliberately are NOT)"
for p in 80 443; do
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port "$p" --cidr 0.0.0.0/0 >/dev/null 2>&1 || echo "    ${p} already open"
done

echo "==> Pushing the RPC node and its site file"
q "mkdir -p ${REMOTE_DIR}/caddy/sites-enabled"
scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/docker-compose.rpc.yml" "${SSH_USER}@${EIP}:${REMOTE_DIR}/docker-compose.rpc.yml"
scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/caddy/Caddyfile"        "${SSH_USER}@${EIP}:${REMOTE_DIR}/caddy/Caddyfile"
scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/caddy/rpc-site.caddy"   "${SSH_USER}@${EIP}:${REMOTE_DIR}/caddy/sites-enabled/02-rpc.caddy"
put_kv() { q "grep -q '^$1=' ${REMOTE_DIR}/.env 2>/dev/null || echo '$1=' >> ${REMOTE_DIR}/.env; \
  sed -i 's|^$1=.*|$1=$2|' ${REMOTE_DIR}/.env; chmod 600 ${REMOTE_DIR}/.env"; }
put_kv RPC_DOMAIN "$RPC_DOMAIN"
put_kv RPC_PUBLIC_URL "https://${RPC_DOMAIN}"
put_kv LXON_SEALER_ENODE "$LXON_SEALER_ENODE"

echo "==> Starting besu-rpc; it full-syncs from genesis before anything is published"
# --no-deps on every bring-up here: adding the rpc overlay must not recreate the sealer just
# because compose is thinking about it. A sealer restart on a 1-validator chain is a gap in
# block production for no reason. The perms one-shot is started explicitly first because
# --no-deps also skips depends_on, and besu-rpc restart-loops without it.
q "cd ${REMOTE_DIR} && ${COMPOSE} up -d --no-deps besu-rpc-perms" >/dev/null
sleep 3
q "cd ${REMOTE_DIR} && ${COMPOSE} up -d --no-deps besu-rpc" >/dev/null
SYNCED=0
for i in $(seq 1 60); do
  raw=$(rq http://besu-rpc:8545 eth_syncing)
  st=$(printf '%s' "$raw" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("false" if d.get("result") is False else "syncing")
except Exception: print("no-answer")')
  h=$(rq http://besu-rpc:8545 eth_blockNumber | jq_result)
  h=$(( ${h:-0} ))
  if [ "$st" = "false" ] && [ "$h" -ge "$SEALER_HEAD" ]; then
    SYNCED=1; echo; echo "    synced to head ${h} after ~$((i*5))s"; break; fi
  printf "\r    %-9s head=%-6s sealer=%-6s %ds" "$st" "$h" "$SEALER_HEAD" $((i*5)); sleep 5
done
[ "$SYNCED" = "1" ] || { echo; echo "ERROR: besu-rpc never reached the sealer's head. Its log:" >&2
  q "docker logs lxon-besu-rpc --tail 40" >&2; exit 1; }

echo "==> Validating the combined proxy config before reloading anything"
if ! q "cd ${REMOTE_DIR} && set -a && . ./.env && set +a && docker run --rm \
    -e EXPLORER_DOMAIN -e RPC_DOMAIN \
    -v ${REMOTE_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
    -v ${REMOTE_DIR}/caddy/sites-enabled:/etc/caddy/sites-enabled:ro \
    caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile" >/dev/null 2>&1; then
  echo "ERROR: the combined Caddyfile does not validate — removing the rpc site so the explorer is untouched:" >&2
  q "rm -f ${REMOTE_DIR}/caddy/sites-enabled/02-rpc.caddy"
  q "docker logs lxon-caddy --tail 10" 2>/dev/null || true
  exit 1
fi
echo "    Valid configuration"

echo "==> Reloading the proxy and the explorer backend"
q "cd ${REMOTE_DIR} && ${COMPOSE} up -d" >/dev/null
CERT=0
for i in $(seq 1 24); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 https://${RPC_DOMAIN} -X POST \
    -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null || echo 000)
  if [ "$code" = "200" ]; then CERT=1; echo "    serving a trusted certificate after ~$((i*5))s"; break; fi
  sleep 5
done
[ "$CERT" = "1" ] || { echo "WARN: https://$RPC_DOMAIN is not answering yet — 'docker logs lxon-caddy --tail 50'. besu-rpc is running; the proxy step is the one to inspect." >&2; }

echo "==> Verifying the public endpoint over TLS"
P="https://${RPC_DOMAIN}"
printf '    chainId      -> %s (0x2d4 = 724)\n' "$(curl -sS -m 12 "$P" -X POST -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | jq_result)"
printf '    blockNumber  -> %s\n' "$(curl -sS -m 12 "$P" -X POST -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | jq_result)"
printf '    peerCount    -> %s\n' "$(rq http://besu-rpc:8545 net_peerCount | jq_result)"
printf '    issuer       -> %s\n' "$(echo | openssl s_client -connect "${RPC_DOMAIN}:443" -servername "$RPC_DOMAIN" 2>/dev/null \
  | openssl x509 -noout -issuer 2>/dev/null | cut -d= -f2-)"
echo "    namespace check — only eth/net/web3 should answer:"
for m in "eth_blockNumber|" "net_listening|" "web3_clientVersion|" \
         "qbft_getValidatorsByBlockNumber|latest" "admin_nodeInfo|" "debug_traceBlockByNumber|latest" \
         "trace_block|latest" "txpool_content|"; do
  name="${m%%|*}"; prm="${m#*|}"
  body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${name}\",\"params\":[${prm}]}"
  verdict=$(curl -sS -m 12 "$P" -X POST -H 'content-type: application/json' -d "$body" 2>/dev/null | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception: print("no-json"); raise SystemExit
print(("ANSWERED" if d.get("result") not in (None,) else "error") if "error" not in d else d["error"]["message"])')
  printf '      %-32s %s\n' "$name" "$verdict"
done
EXPLORER=$(q "sed -n 's/^EXPLORER_DOMAIN=//p' ${REMOTE_DIR}/.env" | head -1)
[ -n "$EXPLORER" ] && printf '    explorer still https -> %s\n' \
  "$(curl -sS -o /dev/null -w '%{http_code}' -m 12 "https://${EXPLORER}/" 2>/dev/null || echo FAIL)"

if [ -f "$DEPLOY_JSON" ]; then
  python3 - "$DEPLOY_JSON" "$RPC_DOMAIN" "$EIP" <<'PY'
import json,sys,datetime
path,host,eip=sys.argv[1:4]
d=json.load(open(path)); n=d.setdefault("node",{})
n["rpcHttp"]=f"https://{host} (read-only ETH,NET,WEB3 on a non-sealing besu-rpc node; the sealer stays 127.0.0.1:8545)"
n["rpcWs"]=f"wss://{host}/ws"
n["rpcLegacyTunnel"]="ssh -i ~/.ssh/lxon-eu-north-1.pem -N -L 8545:127.0.0.1:8545 ubuntu@"+eip
d["updatedAt"]=datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d,open(path,"w"),indent=2); open(path,"a").write("\n")
print(f"    deployment record now advertises https://{host}")
PY
fi

cat <<EOF

Done.
  RPC:  https://${RPC_DOMAIN}   (POST JSON-RPC; ETH, NET, WEB3 only)
  WS:   wss://${RPC_DOMAIN}/ws  ·  /rpc is aliased for the chain-list draft
  The sealer is untouched: still loopback-only, still the only holder of the validator key.
  txpool_* and eth_sendRawTransaction: sending is available on the ETH namespace, which is
  what makes MetaMask work — spam now lands on besu-rpc's 50-peer limit instead of the
  sealer. There is no rate limiting here: Caddy's official image has no rate_limit module.

Rollback to no public RPC (leaves the explorer alone):
  ssh -i ${KEY_FILE} ${SSH_USER}@${EIP} "cd ${REMOTE_DIR} && rm -f caddy/sites-enabled/02-rpc.caddy \\
    && docker compose -f docker-compose.yml -f docker-compose.https.yml up -d"
  Then delete the ${RPC_DOMAIN} A record so nothing published points at a dead host.
EOF
