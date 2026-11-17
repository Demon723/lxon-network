#!/usr/bin/env bash
# Points www.lxon.in at this node and gives Caddy a site for it that SERVES THE WEB UI out of
# /data/ui, 308-redirecting every path it does not recognise to the explorer with path+query intact.
#
#   ./enable-www.sh [--check|--dry-run]
#
#   --check    only prove the DNS actually points here; change nothing
#   --dry-run  print the plan; change nothing
#
# WWW_DOMAIN overrides the name (default www.lxon.in) for a different zone.
#
# Prerequisite: ./enable-https.sh has already run. This extends the caddy service defined by
# docker-compose.https.yml, so without EXPLORER_DOMAIN in ${REMOTE_DIR}/.env compose cannot even
# interpolate the project.
#
# Why the DNS gate is the entire script: an A record for www pointing at a machine that is not this
# one cannot complete an ACME HTTP-01 challenge, so installing the site early produces a Caddy that
# restarts on a name it can never prove, spending part of Let's Encrypt's 30-failed-validations per
# hour budget while adding nothing a visitor can use. www.lxon.in used to resolve to 52.3.226.228
# (an AWS address that is not this account's); the record was moved in the Hostinger panel and as of
# 2026-10-29 it resolves to this instance's EIP from the system resolver, 8.8.8.8, 9.9.9.9 and
# 1.0.0.1, so the gate passes and the certificate is issued. The apex lxon.in still has NO A record
# and is not served by this script — that record is a human's two-minute job in the same panel,
# because this zone is on byte.dns-parking.com / pixel.dns-parking.com, not Route 53, and the
# deployer IAM user has no route53 permission.
#
# NOTE ON THE SITE'S BEHAVIOUR, because this script used to describe it wrongly: caddy/www-site.caddy
# is no longer a redirect-only site. As of 2026-10-29 it serves the landing page at /, the wallet app
# at /app, the assets beside them and the pages' own absolute /ui/... links, and redirects only what
# is left. The verification below therefore asserts BOTH halves: a 200 on / and a path-preserving 308
# on /tx/.... Neither half alone proves the site is right — a redirect-only config passes the 308
# check, and a file_server with no catch-all passes the 200 check while breaking every pasted
# explorer link.
#
# NOTE ON RELOADING, if you edit the site file by hand instead of running this script: the base
# Caddyfile and every file in sites-enabled are read-only FILE bind mounts, so `mv` (and `sed -i`,
# which renames) gives the container a stale inode and `caddy reload` then silently reloads the OLD
# config. Write in place with `cat new > file` and the inode survives; this script sidesteps the
# problem by scp'ing and then recreating.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
KEY_FILE="$HOME/.ssh/lxon-${REGION}.pem"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
WWW_DOMAIN="${WWW_DOMAIN:-www.lxon.in}"
SITE_FILE="03-www.caddy"
DRY_RUN=0; CHECK_ONLY=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --check)   CHECK_ONLY=1 ;;
  "") ;;
  *) echo "usage: ./enable-www.sh [--check | --dry-run]" >&2; exit 2 ;;
esac
[ -f "$KEY_FILE" ] || { echo "ERROR: ${KEY_FILE} missing — run ./deploy.sh first" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EIP=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text)
[ -n "$EIP" ] && [ "$EIP" != "None" ] || { echo "ERROR: EIP not found" >&2; exit 1; }
SSH=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "${SSH_USER}@${EIP}")
q() { "${SSH[@]}" "$@"; }

# Duplicated from the other two enablers so each stays standalone. Query several resolvers and
# require exactly one answer equal to the EIP: 1.1.1.1 alone gives a false negative when this
# network cannot reach Cloudflare, and disagreeing resolvers mean propagation is still in flight.
resolve_all() {
  for r in ${DNS_RESOLVERS:-system 8.8.8.8 9.9.9.9 1.0.0.1}; do
    if [ "$r" = "system" ]; then dig +short A "$1" +time=3 +tries=1 2>/dev/null
    else dig +short A "$1" @"$r" +time=3 +tries=1 2>/dev/null; fi | grep -E '^[0-9.]+$' | head -1
  done | sort -u
}

ANSWERS=$(resolve_all "$WWW_DOMAIN")
NANSWER=$(printf '%s\n' "$ANSWERS" | grep -c . || true)
echo "==> ${WWW_DOMAIN} -> $(printf '%s' "$ANSWERS" | tr '\n' ' ' | sed 's/ $//') | instance EIP is ${EIP}"
if [ "$NANSWER" != "1" ] || [ "$ANSWERS" != "$EIP" ]; then
  cat >&2 <<EOF
ERROR: ${WWW_DOMAIN} does not point at this node, so Caddy could not obtain a certificate for it.
  Change the record in the panel that actually serves the zone (lxon.in is on Hostinger parking
  nameservers byte.dns-parking.com / pixel.dns-parking.com, not Route 53):

      ${WWW_DOMAIN}  A  ${EIP}   TTL 300      (replaces the existing 52.3.226.228)

  Re-check with:  dig +short A ${WWW_DOMAIN} @8.8.8.8
  then run this script again. Refusing here is the point: a site block for a hostname that
  resolves elsewhere is a failing ACME order, not a redirect.
EOF
  exit 1
fi
if [ "$CHECK_ONLY" = "1" ]; then echo "OK: ${WWW_DOMAIN} -> ${EIP}. Safe to run without --check."; exit 0; fi

# Hard prerequisite, not a nicety: the www overlay extends the caddy service that only exists in
# docker-compose.https.yml, and compose refuses to interpolate the project without EXPLORER_DOMAIN.
if ! q "grep -qE ^EXPLORER_DOMAIN=. ${REMOTE_DIR}/.env" 2>/dev/null; then
  echo "ERROR: ${REMOTE_DIR}/.env has no EXPLORER_DOMAIN — run ./enable-https.sh first." >&2
  echo "       This overlay extends the caddy service defined by docker-compose.https.yml; without it" >&2
  echo "       'docker compose config' fails and nothing can be reloaded." >&2
  exit 1
fi
EXPLORER_DOMAIN=$(q "sed -n 's/^EXPLORER_DOMAIN=//p' ${REMOTE_DIR}/.env" | head -1)
echo "==> redirect target is https://${EXPLORER_DOMAIN} (from ${REMOTE_DIR}/.env)"

# Build the -f chain from the overlays that are actually on the instance, in base -> https -> rpc
# -> www order. This matters more than it looks: `docker compose up -d caddy` recreates the proxy
# from the files you name, so omitting docker-compose.rpc.yml would bring caddy back without the
# 02-rpc.caddy mount and take rpc.lxon.in down as a side effect of turning on a redirect. www goes
# last because sequences merge by appending and its caddy stanza only adds a volume.
COMPOSE_CHAIN="-f docker-compose.yml -f docker-compose.https.yml"
if q "test -f ${REMOTE_DIR}/docker-compose.rpc.yml" 2>/dev/null; then
  COMPOSE_CHAIN="${COMPOSE_CHAIN} -f docker-compose.rpc.yml"
else
  echo "note: ${REMOTE_DIR}/docker-compose.rpc.yml is absent, so caddy will be recreated without the RPC overlay."
  echo "      If https://rpc.lxon.in is live, it is served through that file — stop and check before continuing."
fi
COMPOSE="docker compose ${COMPOSE_CHAIN} -f docker-compose.www.yml"

# caddy validate has to see the same environment the container will: sites-enabled can hold
# 02-rpc.caddy, whose {$RPC_DOMAIN} falls back to 127.0.0.1. That fallback keeps the file parsing,
# but linting an address that differs from the live one is not proof the live one still works.
VALIDATE_ENV="-e EXPLORER_DOMAIN=${EXPLORER_DOMAIN} -e WWW_DOMAIN=${WWW_DOMAIN}"
RPC_DOMAIN_LIVE=$(q "sed -n 's/^RPC_DOMAIN=//p' ${REMOTE_DIR}/.env" 2>/dev/null | head -1 || true)
[ -n "$RPC_DOMAIN_LIVE" ] && VALIDATE_ENV="${VALIDATE_ENV} -e RPC_DOMAIN=${RPC_DOMAIN_LIVE}"
validate_config() {
  q "docker run --rm ${VALIDATE_ENV} \
      -v ${REMOTE_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
      -v ${REMOTE_DIR}/caddy/sites-enabled:/etc/caddy/sites-enabled:ro \
      caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile"
}

if [ "$DRY_RUN" = "1" ]; then
  cat <<EOF
DRY RUN — DNS already points here, so nothing would refuse. Would do, in this order:
  1. push caddy/www-site.caddy -> ${REMOTE_DIR}/caddy/sites-enabled/${SITE_FILE}
     (file FIRST: a bind mount whose source is missing is created as an empty directory, and the
      'import sites-enabled/*.caddy' glob would then try to read a directory)
  2. push docker-compose.www.yml -> ${REMOTE_DIR}/docker-compose.www.yml
  3. validate the COMBINED config in a throwaway container: ${COMPOSE_CHAIN} -f docker-compose.www.yml
     with ${VALIDATE_ENV}
  4. only if it validates: cd ${REMOTE_DIR} && ${COMPOSE} up -d --no-deps caddy
     (a few seconds of TLS blip; caddy-data is untouched so no certificate is re-issued,
      --no-deps so blockscout is not recreated as a side effect)
  5. wait for a real leaf certificate on ${WWW_DOMAIN}, then prove BOTH halves of the site:
     200 on / and /app (the UI out of /data/ui) and a path+query-preserving 308 on /tx/0x1234
  rollback on any failure: delete the site file + overlay and reload the previous config
EOF
  exit 0
fi

echo "==> Writing the site file and the overlay"
q "mkdir -p ${REMOTE_DIR}/caddy/sites-enabled"
scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/caddy/www-site.caddy" "${SSH_USER}@${EIP}:${REMOTE_DIR}/caddy/sites-enabled/${SITE_FILE}"
scp -i "$KEY_FILE" -q "${SCRIPT_DIR}/docker-compose.www.yml" "${SSH_USER}@${EIP}:${REMOTE_DIR}/docker-compose.www.yml"

echo "==> Validating the combined config in a throwaway container (nothing is reloaded yet)"
if ! VALIDATE_OUT=$(validate_config 2>&1); then
  echo "ERROR: the combined Caddyfile does not validate. Caddy said:" >&2
  printf '%s\n' "$VALIDATE_OUT" | tail -12 >&2
  echo "       (an 'unrecognized global option: encode' here means a {\$VAR} expanded to nothing," >&2
  echo "        not a broken file — see the note at the top of caddy/Caddyfile)" >&2
  echo "==> removing the www site so the explorer config is exactly what it was" >&2
  q "rm -f ${REMOTE_DIR}/caddy/sites-enabled/${SITE_FILE} ${REMOTE_DIR}/docker-compose.www.yml" || true
  validate_config 2>&1 | tail -4 || true
  exit 1
fi
echo "    combined config validates"

echo "==> Recreating caddy with the new mount"
# --no-deps because caddy depends_on blockscout-frontend/backend with service_started, and compose
# recreates a dependency it thinks has drifted. Rendering the merged chain shows the www overlay adds
# exactly one caddy volume and changes no other service, so nothing here should drift — but this
# stack has already lost the explorer once to an implicit recreate, and a blockscout-backend restart
# is a much bigger blip than caddy's.
q "cd ${REMOTE_DIR} && ${COMPOSE} up -d --no-deps caddy" >/dev/null
sleep 5
q "docker ps --filter name=lxon-caddy --format '{{.Names}}: {{.Status}}'"

echo "==> Reloading caddy, because up -d alone does NOT apply a content-only edit"
# MEASURED on 2026-10-31: with the site file already present and the compose definition unchanged,
# `up -d --no-deps caddy` prints "Container Running" and touches nothing — the container's StartedAt
# stayed 2026-10-29T03:58:00Z with restarts=0 for the whole run. So the @tokenlist CORS handle was on
# disk, validated, and NOT live. The script only ever worked before because its first run ADDED a
# volume, which changes the definition and forces a recreate. Editing this file later would silently
# do nothing.
#
# A reload is the zero-downtime fix, and it works only because scp truncates in place: the bind mount
# keeps its inode, so the container sees the new bytes. `mv`/`sed -i` would swap the inode and the
# reload would re-read the OLD file — the trap documented at the top of enable-ui.sh, at greater
# length there. --force-recreate is reserved for when the mount itself changes.
q "docker exec lxon-caddy sha256sum /etc/caddy/sites-enabled/${SITE_FILE}" | sed 's/^/    container holds: /'
if ! q "docker exec lxon-caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile" >/tmp/www-reload-validate.log 2>&1; then
  echo "ERROR: the config inside the container does not validate; refusing to reload. Caddy said:" >&2
  tail -12 /tmp/www-reload-validate.log >&2
  exit 1
fi
q "docker exec lxon-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile" >/tmp/www-reload.log 2>&1 \
  || { echo "ERROR: caddy reload failed; the running config is still the previous one. Admin API said:" >&2
       tail -8 /tmp/www-reload.log >&2; exit 1; }
echo "    reloaded"
sleep 3

echo "==> Waiting for a leaf certificate on ${WWW_DOMAIN} (ACME http-01, up to 150s)"
CERT=0
for _ in $(seq 1 30); do
  if curl -sS --max-time 10 --connect-to "${WWW_DOMAIN}:443:${EIP}:443" -o /dev/null \
       -w '%{http_code}' "https://${WWW_DOMAIN}/" 2>/dev/null | grep -qE '^(308|301|200)$'; then
    CERT=1; break
  fi
  sleep 5
done
if [ "$CERT" != "1" ]; then
  echo "WARN: https://${WWW_DOMAIN} is not serving yet. ACME may still be in flight." >&2
  q "docker logs lxon-caddy --since 3m 2>&1 | grep -iE '${WWW_DOMAIN}|acme|error' | tail -15" || true
  echo "      If the log shows a failed challenge, re-check the record and roll back:" >&2
  echo "      ssh -i ${KEY_FILE} ${SSH_USER}@${EIP} \"cd ${REMOTE_DIR} && rm -f caddy/sites-enabled/${SITE_FILE} && docker exec lxon-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile\"" >&2
  exit 1
fi

echo "==> Verifying the site serves the UI (a redirect-only config would pass every check below this one)"
# The other half of the site. Without these two assertions a rollback to the pre-2026-10-29
# redirect-only site file passes this script silently, because /tx/0x1234?tab=events still 308s.
UI_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
            --connect-to "${WWW_DOMAIN}:443:${EIP}:443" "https://${WWW_DOMAIN}/" 2>/dev/null || true)
UI_TITLE=$(curl -sS --max-time 15 --connect-to "${WWW_DOMAIN}:443:${EIP}:443" \
             "https://${WWW_DOMAIN}/" 2>/dev/null | grep -o '<title>[^<]*</title>' | head -1 || true)
APP_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
             --connect-to "${WWW_DOMAIN}:443:${EIP}:443" "https://${WWW_DOMAIN}/app" 2>/dev/null || true)
echo "    /     -> ${UI_CODE:-none} ${UI_TITLE:-<no title>}"
echo "    /app  -> ${APP_CODE:-none} (rewritten to app-web.html)"
if [ "${UI_CODE:-}" != "200" ] || [ "${APP_CODE:-}" != "200" ]; then
  echo "ERROR: https://${WWW_DOMAIN} is not serving the UI out of /data/ui." >&2
  echo "       Expected 200 on both / and /app, got '${UI_CODE:-nothing}' and '${APP_CODE:-nothing}'." >&2
  echo "       The volume has to contain the files: check with" >&2
  echo "         ssh -i ${KEY_FILE} ${SSH_USER}@${EIP} \"docker exec lxon-caddy ls /data/ui\"" >&2
  echo "       and re-read the @static matcher in caddy/www-site.caddy — it matches by NAME and SUFFIX," >&2
  echo "       so a file that is absent answers 404 rather than falling through to the redirect." >&2
  exit 1
fi
case "$UI_TITLE" in
  *LXON*) echo "    the landing page answered, not an index of the directory and not the explorer" ;;
  *) echo "WARN: / returned 200 but its <title> is '${UI_TITLE:-none}' — check that /data/ui/landing-light.html is the index." >&2 ;;
esac
# The reason this site file changed on 2026-10-31, so it is a gate and not a print: tokenlists.org
# and the wallet UIs that import a list by URL fetch it from the visitor's browser, and a response
# without Access-Control-Allow-Origin fails in the page while every server-side probe says 200.
# Assert the header on the served bytes, as a browser would send the Origin.
ACAO=$(curl -s -o /dev/null -m 20 -D - --connect-to "${WWW_DOMAIN}:443:${EIP}:443" \
         -H 'origin: https://tokenlists.org' "https://${WWW_DOMAIN}/lxon-token-list.json" 2>/dev/null \
       | awk 'BEGIN{IGNORECASE=1} /^access-control-allow-origin:/{gsub(/\r/,"");print $2}' | head -1)
LIST_CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 20 --connect-to "${WWW_DOMAIN}:443:${EIP}:443" \
               "https://${WWW_DOMAIN}/lxon-token-list.json" 2>/dev/null || true)
echo "    token list: ${LIST_CODE:-none} with access-control-allow-origin=${ACAO:-none}"
if [ "${LIST_CODE:-}" != "200" ] || [ -z "${ACAO:-}" ]; then
  echo "ERROR: the list is not browser-readable. Expected 200 plus an Access-Control-Allow-Origin on" >&2
  echo "       https://${WWW_DOMAIN}/lxon-token-list.json. If the header is missing, the reload above did" >&2
  echo "       not run or the @tokenlist handle is not in the config Caddy actually loaded." >&2
  exit 1
fi

# Informational, not a gate: the @junk handle refuses macOS AppleDouble sidecars, which a `cp -R`
# from a Mac leaves beside every file and which `*.html` would otherwise serve as text/html.
JUNK_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
              --connect-to "${WWW_DOMAIN}:443:${EIP}:443" "https://${WWW_DOMAIN}/ui/._landing-light.html" 2>/dev/null || true)
echo "    dotfile guard: /ui/._landing-light.html -> ${JUNK_CODE:-none} (404 is correct)"

echo "==> Verifying the redirect preserves status, path and query"
# Split the response headers into status and Location instead of printing one glued blob. The
# first version of this line had an unterminated string inside awk's print statement, which is
# exactly how a verification step becomes a silent false negative.
HDRS=$(curl -sSI --max-time 15 --connect-to "${WWW_DOMAIN}:443:${EIP}:443" \
       "https://${WWW_DOMAIN}/tx/0x1234?tab=events" 2>/dev/null | tr -d '\r' || true)
CODE=$(printf '%s\n' "$HDRS" | awk '/^HTTP/{c=$2} END{print c}')
LOCATION=$(printf '%s\n' "$HDRS" | awk 'tolower($0) ~ /^location:/{sub(/^[Ll]ocation:[ \t]*/,""); print}' | head -1)
echo "    status=${CODE:-none} location=${LOCATION:-none}"
case "${CODE:-}" in
  308|301|302|307) ;;
  *) echo "ERROR: expected a redirect from https://${WWW_DOMAIN}, got '${CODE:-nothing}'. Check 'docker logs lxon-caddy'." >&2; exit 1 ;;
esac
case "${LOCATION:-}" in
  *"/tx/0x1234?tab=events") echo "    path and query survived (a pasted /tx link lands on the transaction, not the home page)" ;;
  *) echo "ERROR: Location is '${LOCATION:-none}' — the path did not survive; check {uri} in ${SITE_FILE}." >&2; exit 1 ;;
esac
echo "    explorer still healthy: $(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://${EXPLORER_DOMAIN}/) on https://${EXPLORER_DOMAIN}"
if [ -n "${RPC_DOMAIN_LIVE:-}" ]; then
  RPC_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' "https://${RPC_DOMAIN_LIVE}/" 2>/dev/null || true)
  echo "    rpc still healthy: ${RPC_CODE:-none} on https://${RPC_DOMAIN_LIVE}"
fi
echo "    certificate: $(openssl s_client -connect "${EIP}:443" -servername "${WWW_DOMAIN}" </dev/null 2>/dev/null | openssl x509 -noout -subject -enddate 2>/dev/null | tr '\n' ' ')"
echo "OK: https://${WWW_DOMAIN} serves the web UI from /data/ui (/ -> landing-light.html, /app -> app-web.html)"
echo "    and 308-redirects every other path to https://${EXPLORER_DOMAIN} with path and query intact."
