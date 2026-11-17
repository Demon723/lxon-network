#!/usr/bin/env bash
# Publish the LXON web UI (landing + app view + the dark console pair) at
# https://explorer.lxon.in/ui/ on the explorer node, AND mirror the swap page onto the public
# route https://explorer.lxon.in/swap/ that the listing documents advertise.
#
#   ./enable-ui.sh [--dry-run|--check|--revert]
#
#   --dry-run  print the plan; change nothing
#   --check    verify the live routes only; change nothing. Exits non-zero if /swap/ serves bytes
#              that differ from /data/ui/swap.html, or from UI_EXPECT_SWAP_SHA if that is set; and
#              likewise if the published token list differs from ui/lxon-token-list.json (override
#              with UI_EXPECT_LIST_SHA) or fails the same schema gate a publish is blocked by. Every
#              machine-read endpoint gets an Access-Control-Allow-Origin verdict -- the token list on
#              both origins and /swap/price.json -- because a browser fetch without one fails while
#              every server-side probe still says 200. UI_CORS_URL points the gate elsewhere.
#   --revert   remove the route and /data/ui, then recreate caddy back to the previous config
#              (destructive: /data/ui is snapshotted to ${REMOTE_DIR}/caddy/ first, because the
#               volume holds lxon-token-list.json, which exists nowhere else. A --revert does NOT
#               restore /data/swap/index.html; use the swap-index.html.bak-* it leaves behind.)
#
# WHY THE PUBLIC ROUTE IS SEPARATE: explorer.lxon.in has two independent static roots --
# `handle_path /swap/* { root * /data/swap }` and `handle_path /ui/* { root * /data/ui }` -- and the
# public one serves the file under the name index.html. Until 2026-10-31 this script wrote only
# /data/ui, so /swap/ kept whatever a human had last copied there: after the 2026-10-30 publish the
# advertised URL was serving a 2026-10-28 build with no bridge panel while /ui/swap.html had one.
# The verification that should have caught it printed "routes 200" for /ui/swap.html and never
# looked at /swap/ at all. Hence: publish to both, and assert the bytes served, not the status.
#
# UI_SOURCE_DIR overrides the local folder (default ../../../lxon-web-ui relative to this script's
# repo layout — three levels, because the script is at LXON/LXON/lxon-evm-node/aws/ and the pages
# are at LXON/lxon-web-ui/; the default used to be two levels and so never resolved, which made
# every run fail at the "is not a directory" gate until UI_SOURCE_DIR was set by hand);
# UI_URLS overrides the expected page list.
#
# -----------------------------------------------------------------------------------------------
# Two traps this script exists to avoid, both hit for real on 2026-10-28:
#
# 1. /opt/lxon/caddy/Caddyfile is bind-mounted FILE-BY-FILE (not its directory) and READ-ONLY.
#    Replacing it with `mv` gives the path a new inode while the container keeps reading the old,
#    now-unlinked one — so `caddy reload` reloads the OLD config and reports success. Symptom:
#    host file 3794 bytes, container file 3168 bytes, routes still 404. Write the file IN PLACE
#    (`cat new > file`), which keeps the inode.
# 2. Even in-place is not enough once the inode has already diverged, and `docker compose up -d`
#    will NOT fix it: the mount definition is unchanged, so compose says "Container Running" and
#    does nothing. The mount is re-resolved only by a recreate, hence --force-recreate. The
#    certificates live in the named volume lxon-evm_caddy-data, so a recreate does not re-run ACME
#    (verified: 3 cert files on the volume, 0 ACME log lines after recreate, same leaf to 2027-01-18).
#
# The compose chain must name all four overlays. `docker compose up -d --no-deps --force-recreate
# caddy -f docker-compose.yml` alone would bring caddy back without the rpc and www mounts and take
# rpc.lxon.in and the www site down as a side effect of publishing a web page.
set -uo pipefail

REGION="${REGION:-eu-north-1}"
KEY_FILE="$HOME/.ssh/lxon-${REGION}.pem"
SSH_USER="ubuntu"
REMOTE_DIR="/opt/lxon"
UI_SOURCE_DIR="${UI_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lxon-web-ui" 2>/dev/null && pwd || echo "")}"
# Every file the published UI actually serves. On 2026-11-01 the site was consolidated to three
# pages — / (landing-light.html), /app (app-web.html) and /swap (swap.html) — and the four retired
# variants (index.html "Console", landing.html the dark home, project-website.html, and
# explorer.html, which imitated the real explorer that lives on its own host) were deleted from
# lxon-web-ui. They are NOT in this list any more, and RETIRED_UI_FILES below is what removes them
# from the volume: `docker cp` merges, so dropping a file from the bundle alone leaves the old copy
# being served forever. app.js stays because app-web.html still loads it.
# lxon-token-list.json is deliberately NOT in this list: its source is this directory's own ui/
# folder (TOKEN_LIST below), not the hand-staged web folder, because the list has to be validated
# before it is published and a file that lives in a scratch directory cannot be reviewed. Until
# 2026-10-31 it existed only inside the caddy-data volume, which is why --revert had to snapshot
# /data/ui to keep from destroying the only copy.
UI_FILES=(landing-light.html app-web.html swap.html app.js lxon-auth.json assets)
# Names the www route table still 301s (so old links and the listing submissions keep working) but
# which must no longer resolve to a page on the explorer's /ui/ host.
RETIRED_UI_FILES=(index.html landing.html project-website.html explorer.html)
MARKER='# Anything that is not API traffic is the Next.js UI.'
MODE="${1:-}"
case "$MODE" in --dry-run|--check|--revert|"") ;; *) echo "usage: $0 [--dry-run|--check|--revert]" >&2; exit 2 ;; esac
[ -n "$UI_SOURCE_DIR" ] && [ -d "$UI_SOURCE_DIR" ] || { echo "ERROR: UI_SOURCE_DIR='$UI_SOURCE_DIR' is not a directory" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET="$SCRIPT_DIR/ui/ui-route.caddy"
[ -f "$SNIPPET" ] || { echo "ERROR: missing $SNIPPET" >&2; exit 1; }
TOKEN_LIST="$SCRIPT_DIR/ui/lxon-token-list.json"
VALIDATE_LIST="$SCRIPT_DIR/ui/validate_token_list.py"
# A token list is read by software that will not tell you it rejected one: MetaMask, Uniswap and
# tokenlists.org each validate first and drop the silent fail, so an invalid list is worse than no
# list -- it looks published while doing nothing. Publishing without validating is exactly what
# happened to v2.0.0, which has been live since 2026-10-28 with an unchecksummed LXON address and
# four schema-pattern violations. The gate is therefore not optional and not skippable: if python3,
# cast or the validator is missing, the publish stops rather than shipping something unverified.
if [ -f "$TOKEN_LIST" ] && [ "$MODE" != "--revert" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required to validate $TOKEN_LIST" >&2; exit 1; }
  command -v cast >/dev/null 2>&1 || { echo "ERROR: foundry's cast is required to compute EIP-55 checksums for $TOKEN_LIST" >&2; exit 1; }
  [ -f "$VALIDATE_LIST" ] || { echo "ERROR: missing $VALIDATE_LIST" >&2; exit 1; }
  echo "==> validating the token list (schema + checksums + logoURI reachability)"
  python3 "$VALIDATE_LIST" "$TOKEN_LIST" || { echo "ERROR: token list failed validation; nothing was published" >&2; exit 1; }
else
  echo "NOTE: no token list at $TOKEN_LIST -- the published list will not change"
fi

# `Name=tag:Name,Values=...` is the only form the CLI accepts; this line used to read
# `Name:Tag,Tag:Name=lxon-node-eip`, which fails ParamValidation, and the 2>/dev/null below turned
# that into the misleading "could not resolve the node EIP". Every other enabler in this directory
# already used the correct form. Drop the stderr redirect if this ever fails again — the CLI's own
# message is the diagnosis.
EIP=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Name,Values=lxon-node-eip" --query 'Addresses[0].PublicIp' --output text)
{ [ -n "$EIP" ] && [ "$EIP" != "None" ]; } || { echo "ERROR: could not resolve the node EIP" >&2; exit 1; }
SSH=(ssh -i "$KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "${SSH_USER}@${EIP}")
q() { "${SSH[@]}" "$@"; }

if [ "$MODE" = "--check" ]; then
  CHECK_RC=0
  echo "==> probing https://${EIP} as explorer.lxon.in"
  for u in /ui/ /ui/app-web.html /ui/landing-light.html /ui/assets/lxon-mark-192.png \
           / /swap/price.json /ui/lxon-token-list.json; do
    printf '  %-40s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' -m 20 "https://explorer.lxon.in$u")"
  done

  # The public swap URL, checked BY BYTES. /swap/* is served from /data/swap and /ui/* from /data/ui
  # -- two independent Caddy roots -- and this script only published to /data/ui, so on 2026-10-30 a
  # "routes 200" table went green while explorer.lxon.in/swap/, the URL in the listing documents, kept
  # serving a day-old build with no bridge panel. A status code cannot see that; a digest can.
  # Reference: UI_EXPECT_SWAP_SHA if given, else whatever /data/ui/swap.html holds on the node.
  echo "==> the public swap route, compared by digest"
  served_sha=$(curl -sL -m 30 "https://explorer.lxon.in/swap/" | shasum -a 256 | awk '{print $1}')
  if [ -n "${UI_EXPECT_SWAP_SHA:-}" ]; then
    want_sha="${UI_EXPECT_SWAP_SHA}"; want_src="UI_EXPECT_SWAP_SHA"
  else
    want_sha=$(q "docker exec lxon-caddy sha256sum /data/ui/swap.html" 2>/dev/null | awk '{print $1}')
    want_src="/data/ui/swap.html on the node"
  fi
  printf '  %-40s page sha %s\n' "/swap/" "${served_sha:-none}"
  if [ -z "$served_sha" ]; then
    echo "      MISS: the public route returned no bytes"; CHECK_RC=1
  elif [ -z "$want_sha" ]; then
    echo "      NOT CHECKED: no reference digest (UI_EXPECT_SWAP_SHA unset and the node unreadable)"
  elif [ "$served_sha" = "$want_sha" ]; then
    echo "      OK: matches ${want_src} (${want_sha:0:12}...)"
  else
    echo "      MISS: expected ${want_sha:0:12}... from ${want_src}; the two roots have diverged"
    echo "            /swap/ serves /data/swap/index.html, /ui/swap.html serves /data/ui/swap.html"
    CHECK_RC=1
  fi

  echo "==> the same list on the www origin"
  printf '  %-40s %s\n' "/lxon-token-list.json" "$(curl -s -o /dev/null -w '%{http_code}' -m 20 "https://www.lxon.in/lxon-token-list.json")"

  # CORS, as a verdict rather than a print. A token list is fetched by tokenlists.org from the
  # visitor's browser, and by several DEX front-ends; without Access-Control-Allow-Origin the fetch
  # fails inside the page while curl, an address bar and every status code on this server say the
  # list is fine. --check used to print the header's value (empty) and exit 0, which is the same
  # mistake as the piped `tail -3` above: a reported failure thrown away.
  # Both URLs the list is published at are gated, because a submission can name either. Checking only
  # www is what let explorer.lxon.in/ui/lxon-token-list.json stay unreadable after "the CORS check
  # passed". UI_CORS_URL exists to prove the gate can refuse: point it at any served URL that carries
  # no ACAO (https://www.lxon.in/landing-light.html does not) and the check must exit non-zero.
  echo "==> the machine-read endpoints, as a browser sees them"
  if [ -n "${UI_CORS_URL:-}" ]; then
    cors_urls="${UI_CORS_URL}"
  else
    # Every URL a browser on ANOTHER origin fetches. The token list is published at two of them and a
    # submission can name either, so checking one is not enough (that is T10). price.json is here for
    # the same reason -- any front-end quoting LXON in USD reads it from a script tag, and until
    # 2026-10-31 it answered 200 with no ACAO while --check only ever named the list (that is T11).
    # HTML is deliberately NOT in this set: /swap/ and /ui/ pages keep no wildcard.
    cors_urls="https://explorer.lxon.in/ui/lxon-token-list.json https://www.lxon.in/lxon-token-list.json"
    cors_urls="$cors_urls https://explorer.lxon.in/swap/price.json"
  fi
  for cors_url in $cors_urls; do
    acao=$(curl -s -o /dev/null -m 20 -D - -H 'origin: https://tokenlists.org' "$cors_url" \
      | awk 'BEGIN{IGNORECASE=1} /^access-control-allow-origin:/{gsub(/\r/,"");print $2}' | head -1)
    printf '  %-52s cors verdict %s\n' "$cors_url" "${acao:-none}"
    if [ -z "$acao" ]; then
      echo "      MISS: no Access-Control-Allow-Origin, so a cross-origin fetch of this endpoint fails"
      echo "            token list -- explorer: ui/ui-route.caddy's header line inside handle_path /ui/*"
      echo "                        (it matches the STRIPPED path, so the rule names /lxon-token-list.json)"
      echo "              token list -- www:      caddy/www-site.caddy's @tokenlist handle, ./enable-www.sh"
      echo "              price feed -- explorer: the header line inside handle_path /swap/*, naming"
      echo "                        /price.json (also stripped), then caddy reload -- never mv/sed -i"
      CHECK_RC=1
    elif [ "$acao" = "*" ]; then
      echo "      OK: '*' -- a read-only public endpoint needs no credential, so a wildcard is the correct scope"
    else
      echo "      OK: ${acao} (an allowlist: every importing origin has to be named here)"
    fi
  done
  # The token list, checked BY BYTES on both origins -- the same defect class as /swap/. The
  # schema gate below already ran over the published bytes, printed
  # "RESULT: FAIL (5 failed, 2 not run)" -- and --check still exited 0. A check that reports a
  # failure and then reports success is not a check. What is live is v2.0.0 (1,302 B, 2 tokens, an
  # unchecksummed LXON address, four schema-pattern violations); the repo carries a v3.0.0 list
  # that passes this same validator with 0 failed / 0 not run.
  # The reference is the repo file, NOT the served bytes: a digest compared against what was just
  # fetched can never fail (see the /swap/ root, where "matches /data/ui" was the meaningful half).
  echo "==> the published token list, compared by digest (both origins)"
  if [ -n "${UI_EXPECT_LIST_SHA:-}" ]; then
    list_ref="${UI_EXPECT_LIST_SHA}"; list_ref_src="UI_EXPECT_LIST_SHA"
  elif [ -f "$TOKEN_LIST" ]; then
    list_ref=$(shasum -a 256 "$TOKEN_LIST" | awk '{print $1}')
    list_ref_src="ui/lxon-token-list.json, the file the publish gate validates"
  else
    list_ref=""; list_ref_src="none (no repo token list and UI_EXPECT_LIST_SHA unset)"
  fi
  for u in /ui/lxon-token-list.json /lxon-token-list.json; do
    host="explorer.lxon.in"; [ "$u" = "/lxon-token-list.json" ] && host="www.lxon.in"
    lp=$(mktemp) || { echo "      NOT CHECKED: mktemp failed"; CHECK_RC=1; continue; }
    curl -sL -m 30 "https://$host$u" -o "$lp"
    ls_=$(shasum -a 256 "$lp" | awk '{print $1}')
    printf '  %-52s list sha %s\n' "$host$u" "${ls_:-none}"
    if [ ! -s "$lp" ]; then
      echo "      MISS: the origin returned no bytes"; CHECK_RC=1
    elif [ -z "$list_ref" ]; then
      echo "      NOT CHECKED: no reference digest ($list_ref_src)"
    elif [ "$ls_" = "$list_ref" ]; then
      echo "      OK: matches ${list_ref_src} (${list_ref:0:12}...)"
    else
      echo "      MISS: served ${ls_:0:12}... vs ${list_ref:0:12}... from ${list_ref_src}"
      echo "            the repo list has been edited (or never published); a publish puts it right"
      CHECK_RC=1
    fi
    rm -f "$lp"
  done

  echo "==> the published list against the same schema the gate uses"
  curl -s -m 20 "https://www.lxon.in/lxon-token-list.json" -o /tmp/published-token-list.json \
    || { echo "      MISS: could not fetch the published list"; CHECK_RC=1; }
  # The validator exits 1 when any check FAILs. That verdict used to be piped into `tail -3`,
  # which threw it away, so a failing published list printed FAIL and the run still reported OK.
  if python3 "$VALIDATE_LIST" /tmp/published-token-list.json --no-net >/tmp/published-token-list.validate.log 2>&1; then
    tail -3 /tmp/published-token-list.validate.log
  else
    tail -8 /tmp/published-token-list.validate.log
    echo "      MISS: the published list does not satisfy the gate that blocks a publish"
    CHECK_RC=1
  fi
  exit $CHECK_RC
fi

# The remote half. Quoted with 'EOF' so nothing expands locally; the two values it needs are
# passed through the environment.
read -r -d '' REMOTE <<'REMOTE_EOF' || true
set -uo pipefail
cd /opt/lxon || exit 1
ENV=/opt/lxon/.env
EXPLORER_DOMAIN=$(sed -n 's/^EXPLORER_DOMAIN=//p' "$ENV" | head -1)
RPC_DOMAIN=$(sed -n 's/^RPC_DOMAIN=//p' "$ENV" | head -1)
CHAIN=(-f docker-compose.yml -f docker-compose.https.yml -f docker-compose.rpc.yml -f docker-compose.www.yml)
CF=caddy/Caddyfile
RC=0
# This half runs under a QUOTED heredoc, so the local bash array cannot reach it; the retired page
# names arrive as UI_RETIRED, space-separated. An unset value means "purge nothing" — the safe
# direction, because a wrong guess here deletes a live page, while an empty list only leaves one up.
read -r -a RETIRED_UI_FILES <<<"${UI_RETIRED:-}"
[ -n "$EXPLORER_DOMAIN" ] || { echo "FAIL: no EXPLORER_DOMAIN in $ENV"; exit 1; }
docker ps --format '{{.Names}}' | grep -qx lxon-caddy || { echo "FAIL: lxon-caddy not running"; exit 1; }

check() { # check <want> <url> [extra curl args...]
  local want="$1" url="$2"; shift 2
  local got; got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@" "$url")
  printf '  %-58s %s  want %s' "$url" "${got:-none}" "$want"
  [ "$got" = "$want" ] && echo "" || { echo "   <-- MISS"; RC=1; }
}

if [ "${UI_REVERT:-0}" = "1" ]; then
  latest=$(ls -1t caddy/Caddyfile.bak-ui-* 2>/dev/null | head -1)
  [ -n "$latest" ] || { echo "FAIL: no Caddyfile.bak-ui-* to restore"; exit 1; }
  cat "$latest" > "$CF"                       # in place: keeps the mounted inode
  # Snapshot before deleting. /data/ui holds files that are not in the bundle this script can rebuild
  # — explorer.html and swap.html arrived here by hand once, and until 2026-10-31 so did
  # lxon-token-list.json, whose only copy was inside the volume. A revert that drops them breaks links
  # on a second hostname, so the volume is archived even though the token list now has a repo source.
  snap="caddy/ui-snapshot-$(date -u +%Y%m%dT%H%M%SZ).tgz"
  docker exec lxon-caddy tar czf /tmp/ui-snapshot.tgz -C /data ui 2>/dev/null \
    && docker cp lxon-caddy:/tmp/ui-snapshot.tgz "$snap" \
    && echo "    /data/ui snapshotted to /opt/lxon/${snap}" \
    || echo "WARN: could not snapshot /data/ui — reverting anyway, but the volume's unique files are gone"
  docker exec lxon-caddy rm -rf /data/ui
  docker compose "${CHAIN[@]}" up -d --no-deps --force-recreate caddy >/dev/null 2>&1
  echo "reverted from $latest"; exit 0
fi

echo "==> staging the bundle"
rm -rf /tmp/ui-stage && mkdir -p /tmp/ui-stage || exit 1
tar xzf /tmp/ui-bundle.tgz -C /tmp/ui-stage 2>/dev/null || { echo "FAIL: extract"; exit 1; }
# Purge again on this side: the tarball may have been built on a machine that does not set
# COPYFILE_DISABLE, and a `._name.html` published into /data/ui is served as text/html.
find /tmp/ui-stage \( -name '._*' -o -name '.DS_Store' \) -exec rm -f {} + 2>/dev/null || true
for f in landing-light.html app-web.html swap.html lxon-auth.json assets/lxon-mark-192.png; do
  [ -f "/tmp/ui-stage/$f" ] || { echo "FAIL: bundle missing $f"; exit 1; }
done
echo "    $(find /tmp/ui-stage -type f | wc -l) files"

echo "==> copying into the caddy-data volume (/data/ui)"
docker exec lxon-caddy mkdir -p /data/ui || exit 1
docker cp /tmp/ui-stage/. lxon-caddy:/data/ui/ || exit 1
# `docker cp` MERGES. Removing a file from the bundle does not remove it from the volume, so without
# this step the four retired variants would keep answering 200 at explorer.lxon.in/ui/<name>.html
# forever, which is the opposite of what a delete means. Archived first, so the volume's copy is not
# the only record — the local tarball is, but this costs nothing and a snapshot has been the rule
# every time this script has destroyed volume state.
if [ "${#RETIRED_UI_FILES[@]}" -gt 0 ]; then
  docker exec lxon-caddy tar czf /tmp/ui-retired.tgz -C /data/ui "${RETIRED_UI_FILES[@]}" 2>/dev/null \
    && docker cp lxon-caddy:/tmp/ui-retired.tgz "caddy/ui-retired-$(date -u +%Y%m%dT%H%M%SZ).tgz" 2>/dev/null \
    && echo "    retired pages archived under caddy/ before removal" \
    || echo "    NOTE: nothing to archive (already removed on this box)"
  for f in "${RETIRED_UI_FILES[@]}"; do
    docker exec lxon-caddy rm -f "/data/ui/${f}" "/data/ui/._${f}"
  done
  echo "    retired variants removed from the volume: ${RETIRED_UI_FILES[*]}"
fi
docker exec lxon-caddy chmod -R a+rX /data/ui || exit 1

echo "==> mirroring the swap page onto the PUBLIC route (/data/swap/index.html)"
# Why this exists: `handle_path /swap/* { root * /data/swap }` and `handle_path /ui/* { root *
# /data/ui }` are two different static roots, and the filename differs too (index.html, not
# swap.html). Publishing only /data/ui leaves the URL that appears in the listing documents and
# every share link serving whatever was last put there by hand -- which is how /swap/ showed a build
# with no bridge panel for a day after a green publish.
# price.json is deliberately not touched: the 5-minute cron owns it.
if docker exec lxon-caddy test -d /data/swap; then
  pbak="caddy/swap-index.html.bak-$(date -u +%Y%m%dT%H%M%SZ)"
  docker cp lxon-caddy:/data/swap/index.html "$pbak" 2>/dev/null \
    && echo "    previous public page kept at /opt/lxon/${pbak}" \
    || echo "    NOTE: no /data/swap/index.html to back up (first mirror on this box)"
  price_before=$(docker exec lxon-caddy sha256sum /data/swap/price.json 2>/dev/null | awk '{print $1}')
  docker exec lxon-caddy cp /data/ui/swap.html /data/swap/index.html \
    && docker exec lxon-caddy chmod a+r /data/swap/index.html \
    || { echo "FAIL: could not publish the public route"; RC=1; }
  # Assert the post-state, do not trust the copy's exit code: the two routes must now be the same
  # bytes, and the feed must be exactly where it was.
  ui_sha=$(docker exec lxon-caddy sha256sum /data/ui/swap.html 2>/dev/null | awk '{print $1}')
  sw_sha=$(docker exec lxon-caddy sha256sum /data/swap/index.html 2>/dev/null | awk '{print $1}')
  if [ -n "$ui_sha" ] && [ "$ui_sha" = "$sw_sha" ]; then
    echo "    /data/swap/index.html == /data/ui/swap.html (${sw_sha:0:12}...)"
  else
    echo "FAIL: public route holds ${sw_sha:-absent}, expected ${ui_sha:-unreadable from /data/ui}"; RC=1
  fi
  price_after=$(docker exec lxon-caddy sha256sum /data/swap/price.json 2>/dev/null | awk '{print $1}')
  [ "$price_before" = "$price_after" ] \
    || { echo "FAIL: /data/swap/price.json changed during the mirror (${price_before:-absent} -> ${price_after:-absent})"; RC=1; }
else
  echo "    NOTE: /data/swap does not exist on this box; the public route was not mirrored"
fi

echo "==> installing the route IN PLACE (never mv over a file bind mount)"
bak="caddy/Caddyfile.bak-ui-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$CF" "$bak" || exit 1
if grep -q 'handle_path /ui' "$CF"; then
  echo "    route already present; leaving the file alone"
else
  grep -qxF "	$MARKER" "$CF" || { echo "FAIL: insertion marker absent; refusing to guess a location"; exit 1; }
  awk -v marker="	$MARKER" -v snip="$UI_SNIPPET_PATH" '
    BEGIN { while ((getline l < snip) > 0) if (l !~ /^[ \t]*#/) add = add l "\n" }
    index($0, marker) == 1 && !done { printf "%s", add; print ""; done = 1 }
    { print }
  ' "$CF" > /tmp/Caddyfile.ui.new || { echo "FAIL: awk"; exit 1; }
  [ "$(grep -c 'handle_path /ui' /tmp/Caddyfile.ui.new)" = "1" ] || { echo "FAIL: expected exactly one /ui route"; exit 1; }
  cat /tmp/Caddyfile.ui.new > "$CF" || { echo "FAIL: in-place write"; cp -p "$bak" "$CF"; exit 1; }
  chmod 644 "$CF"
  echo "    inserted; backup at $bak"
fi

echo "==> validating before anything is reloaded"
VAL_ENV="-e EXPLORER_DOMAIN=$EXPLORER_DOMAIN"; [ -n "$RPC_DOMAIN" ] && VAL_ENV="$VAL_ENV -e RPC_DOMAIN=$RPC_DOMAIN"
# shellcheck disable=SC2086
docker run --rm $VAL_ENV -v /opt/lxon/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v /opt/lxon/caddy/sites-enabled:/etc/caddy/sites-enabled:ro \
  caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/tmp/ui-val.log 2>&1 \
  || { echo "FAIL: does not validate; restoring"; tail -12 /tmp/ui-val.log; cat "$bak" > "$CF"; exit 1; }
echo "    validates"

echo "==> recreating caddy (plain up -d will not re-resolve a changed file mount)"
# shellcheck disable=SC2086
docker compose "${CHAIN[@]}" up -d --no-deps --force-recreate caddy 2>&1 | tail -2
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "https://$EXPLORER_DOMAIN/swap/price.json")" = "200" ] && break
  sleep 4
done

echo "==> proof the container holds the new file"
hb=$(stat -c %s "$CF"); cb=$(docker exec lxon-caddy stat -c %s /etc/caddy/Caddyfile)
echo "    host $hb bytes / container $cb bytes / routes in container: $(docker exec lxon-caddy grep -c 'handle_path /ui' /etc/caddy/Caddyfile)"
[ "$hb" = "$cb" ] || { echo "FAIL: container still holds a different inode — restore $bak and investigate"; cat "$bak" > "$CF"; RC=1; }

echo "==> routes"
check 200 "https://$EXPLORER_DOMAIN/ui/"
check 200 "https://$EXPLORER_DOMAIN/ui/app-web.html"
check 200 "https://$EXPLORER_DOMAIN/ui/landing-light.html"
# The delete has to be proven, not assumed: a bundle that no longer contains a file says nothing
# about whether the volume still serves it. These are the assertions that would have caught the
# 2026-10-31 shape, where four retired homes stayed reachable on the explorer host.
for f in "${RETIRED_UI_FILES[@]}"; do
  check 404 "https://$EXPLORER_DOMAIN/ui/${f}"
done
check 200 "https://$EXPLORER_DOMAIN/ui/assets/lxon-mark-192.png"
check 200 "https://$EXPLORER_DOMAIN/ui/lxon-token-list.json"
# The list is read by machines that validate before importing, so "200" is not proof it is the list
# we signed up to publish. Compare the bytes actually in the volume against the file this run
# validated; a publish that silently ships a different list is the v2.0.0 failure all over again.
if [ -n "${TOKEN_LIST_SHA:-}" ]; then
  vol=$(docker exec lxon-caddy sha256sum /data/ui/lxon-token-list.json 2>/dev/null | awk '{print $1}')
  if [ "$vol" = "$TOKEN_LIST_SHA" ]; then
    echo "    token list in /data/ui matches the validated file (${vol:0:12}...)"
  else
    echo "    FAIL: /data/ui/lxon-token-list.json is ${vol:-absent}, expected ${TOKEN_LIST_SHA:0:12}..."; RC=1
  fi
fi
echo "==> nothing else moved"
check 200 "https://$EXPLORER_DOMAIN/"
check 200 "https://$EXPLORER_DOMAIN/swap/"
# The status check above cannot tell a fresh page from a stale one, and a stale page at this URL is
# the incident this script now prevents. Assert the bytes actually served against the volume file
# the mirror just wrote -- this is what proves the advertised URL moved, not just that it answered.
swap_served=$(curl -sL --max-time 25 "https://$EXPLORER_DOMAIN/swap/" | sha256sum | awk '{print $1}')
swap_volume=$(docker exec lxon-caddy sha256sum /data/swap/index.html 2>/dev/null | awk '{print $1}')
printf '  %-58s page sha %s' "https://$EXPLORER_DOMAIN/swap/" "${swap_served:0:12}..."
if [ -n "$swap_served" ] && [ "$swap_served" = "$swap_volume" ]; then
  echo "  OK (== /data/swap/index.html)"
else
  echo "  MISS (served ${swap_served:-none}, volume ${swap_volume:-unreadable})"; RC=1
fi
check 200 "https://$EXPLORER_DOMAIN/swap/price.json"
check 200 "https://$EXPLORER_DOMAIN/api/v2/stats"
# www.lxon.in serves the SAME /data/ui as /ui/ here, so a bundle publish moves both hostnames and
# both have to be asserted. This block used to be one line — `check 308 "https://www.lxon.in/"` —
# which was correct while www was a redirect-only site and became a guaranteed false MISS the day
# www started serving the UI (2026-10-29), i.e. it would have told the next operator to roll back a
# perfectly good publish. Guarded on the site file existing so this script still passes on a box
# that has not run enable-www.sh.
if [ -f caddy/sites-enabled/03-www.caddy ]; then
  echo "==> www.lxon.in (same volume, both halves of the site)"
  # ONE URL PER PAGE, since 2026-11-01. The three pages answer at /, /app and /swap; every retired
  # address must REDIRECT to its canonical one rather than serve a second copy, so the redirects
  # are the assertion, not an afterthought.
  #
  # This block used to check that /explorer.html and /swap.html answered 200 — and the first
  # publish after the consolidation failed on exactly those two lines, because the site now 301s
  # them on purpose. That is the same failure mode as the stale `check 308 https://www.lxon.in/`
  # described above: a checker that asserts the previous design tells the next operator to roll
  # back a perfectly good publish. If you are here because one of these lines missed, read
  # caddy/www-site.caddy first and decide which of the two is wrong.
  check 200 "https://www.lxon.in/"
  check 200 "https://www.lxon.in/app"
  check 200 "https://www.lxon.in/swap"
  check 200 "https://www.lxon.in/swap/price.json"
  check 200 "https://www.lxon.in/lxon-token-list.json"
  # The sign-in panel fetches this when it opens and shows "not configured" when googleClientId is
  # empty. A 200 that is not the file — an HTML error page, or a JSON body missing the field — would
  # leave a dead button that reports nothing, so the body is checked, not just the status.
  check 200 "https://www.lxon.in/lxon-auth.json"
  if curl -s --max-time 20 "https://www.lxon.in/lxon-auth.json" | grep -q '"googleClientId"'; then
    echo "  lxon-auth.json carries the googleClientId field"
  else
    echo "   <-- MISS: lxon-auth.json served without googleClientId"; RC=1
  fi
  # /ui/assets/* is still SERVED on www, not redirected: listing and aggregator documents carry
  # /ui/assets/... URLs and a cross-host redirect would move the problem rather than fix it.
  check 200 "https://www.lxon.in/ui/assets/lxon-mark-192.png"
  check 301 "https://www.lxon.in/swap.html"
  check 301 "https://www.lxon.in/app-web.html"
  check 301 "https://www.lxon.in/landing-light.html"
  check 301 "https://www.lxon.in/index.html"
  check 301 "https://www.lxon.in/landing.html"
  check 301 "https://www.lxon.in/project-website.html"
  check 301 "https://www.lxon.in/explorer.html"
  check 301 "https://www.lxon.in/ui/"
  # 302, deliberately not 308: a permanent redirect to a host that does not serve these paths gets
  # cached in browsers and cannot be undone from the server. See the CAUTION in www-site.caddy.
  check 302 "https://www.lxon.in/signin"
  check 308 "https://www.lxon.in/blocks"
  check 404 "https://www.lxon.in/ui/._landing-light.html"
  # And the same bytes-not-status rule as /swap/: a 200 on / proves a page answered, not that the
  # bundle this run just pushed is what came back. Compare the served home page to the volume file.
  home_served=$(curl -s --max-time 25 "https://www.lxon.in/" | sha256sum | awk '{print $1}')
  home_volume=$(docker exec lxon-caddy sha256sum /data/ui/landing-light.html 2>/dev/null | awk '{print $1}')
  printf '  %-58s page sha %s' "https://www.lxon.in/" "${home_served:0:12}..."
  if [ -n "$home_served" ] && [ "$home_served" = "$home_volume" ]; then
    echo "  OK (== /data/ui/landing-light.html)"
  else
    echo "  MISS (served ${home_served:-none}, volume ${home_volume:-unreadable})"; RC=1
  fi
else
  echo "==> www.lxon.in not installed (no caddy/sites-enabled/03-www.caddy); skipping its routes"
fi
[ -n "$RPC_DOMAIN" ] && check 200 "https://$RPC_DOMAIN/" -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
echo "==> certificates survived"
docker exec lxon-caddy sh -c 'find /data/caddy/certificates -name "*.json" | wc -l' | sed 's/^/    cert files: /'
docker logs lxon-caddy --since 3m 2>&1 | grep -icE 'acme' | sed 's/^/    ACME lines (want 0): /'

[ "$RC" = 0 ] && echo "OK: /ui live on https://$EXPLORER_DOMAIN/ui/" \
              || echo "FAIL: a check missed. Rollback: cat $bak > $CF && docker compose ${CHAIN[*]} up -d --no-deps --force-recreate caddy"
exit $RC
REMOTE_EOF

if [ "$MODE" = "--dry-run" ]; then
  cat <<EOF
DRY RUN — would do, in this order:
  1. tar the bundle from ${UI_SOURCE_DIR}: ${UI_FILES[*]}
     (plus ui/lxon-token-list.json from this repo, validated against the token-list schema first)
  2. scp it to ${EIP}:/tmp/ui-bundle.tgz
  3. docker cp into lxon-caddy:/data/ui  (caddy-data named volume, so it survives a recreate)
  3a. archive, then rm, the retired variants from the volume: ${RETIRED_UI_FILES[*]}
      (docker cp merges, so without this the deleted pages keep answering 200 on /ui/)
  3b. mirror /data/ui/swap.html to /data/swap/index.html -- a DIFFERENT static root, and the URL
      the listing documents advertise. The previous copy is kept at
      /opt/lxon/caddy/swap-index.html.bak-<UTC>, price.json is left alone, and the mirror is
      asserted by digest rather than trusted.
  4. back up ${REMOTE_DIR}/caddy/Caddyfile, then insert ui/ui-route.caddy before the catch-all
     handle — with cat > file, NOT mv, because the Caddyfile is a read-only FILE bind mount and
     an mv leaves the container reading the old inode
  5. caddy validate in a throwaway container with EXPLORER_DOMAIN and RPC_DOMAIN taken from .env
  6. docker compose -f docker-compose.yml -f docker-compose.https.yml \\
         -f docker-compose.rpc.yml -f docker-compose.www.yml up -d --no-deps --force-recreate caddy
  7. assert /ui/* == 200 AND explorer home, /swap/, /swap/price.json, /api/v2/stats, rpc
     eth_blockNumber, and — if the www site is installed — www's own halves: / /app /swap 200, the
     retired addresses 301 to their canonical path, /signin 302 (NOT 308 — a cached permanent
     redirect there is unrecoverable from the server), /blocks 308, a dotfile 404; all still answer;
     PLUS the bytes served at /swap/ equal /data/swap/index.html and the bytes served at / equal
     /data/ui/landing-light.html, because 200 says nothing about which build is answering.
     Restore the backup on any miss.
  rollback: ./enable-ui.sh --revert  (and cp the retained swap-index.html.bak-* back into the volume)
EOF
  exit 0
fi

echo "==> building the bundle from ${UI_SOURCE_DIR}"
STAGE=$(mktemp -d) || exit 1
for f in "${UI_FILES[@]}"; do cp -R "${UI_SOURCE_DIR}/${f}" "${STAGE}/" || { echo "ERROR: missing ${f}" >&2; rm -rf "$STAGE"; exit 1; }; done
# The token list rides in the same bundle, from the repo rather than from the scratch web folder, so
# the published copy always has a reviewable source. Absent is allowed (a repo state without one) and
# says so; present-but-invalid already stopped the run above.
if [ -f "$TOKEN_LIST" ]; then
  cp "$TOKEN_LIST" "${STAGE}/lxon-token-list.json" || { echo "ERROR: could not stage the token list" >&2; rm -rf "$STAGE"; exit 1; }
  # One line of python on purpose: bash 3.2 on this Mac mis-parses a multi-line program inside "$( )".
  TL_SUMMARY=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d["version"]; print("v%d.%d.%d, %d tokens" % (v["major"], v["minor"], v["patch"], len(d["tokens"])))' "$TOKEN_LIST") \
    || { echo "ERROR: the token list is not readable JSON" >&2; rm -rf "$STAGE"; exit 1; }
  TL_SHA=$(shasum -a 256 "$TOKEN_LIST" | awk '{print $1}')
  echo "    token list: $TL_SUMMARY (sha256 ${TL_SHA:0:12}...)"
else
  TL_SHA=""
fi
# macOS AppleDouble sidecars, guarded on the way in.
#
# MEASURED, not assumed: on 2026-10-29 twelve `._*` files (including `._.` for the directory itself
# and `._assets`) were live in /data/ui and publicly served — `*.html` in www's @static matcher
# matches `._landing-light.html`, so binary xattr metadata was being answered as text/html. Their
# content is a com.apple.provenance ATTR blob, 163 bytes each.
#
# What did NOT create them: this script's own path. `cp -R` from lxon-web-ui carries the
# com.apple.provenance xattr, but bsdtar 3.5.3 archives it as nothing — measured 0 `._` entries both
# with and without `--mac-metadata`. So the sidecars arrived by a different route, and the shape of
# the set (one per entry plus one for the directory) is what macOS writes when files are staged
# through a volume that cannot hold xattrs — the exFAT pendrive, a Finder-made archive, or an
# SMB/AFP copy — where the sidecar becomes a real file that any subsequent `cp -R` faithfully
# carries along.
#
# The purge and the assertion below therefore cost nothing and are not fixing this script's own bug:
# they stop whatever the next person stages from being published, and turn a repeat into a loud
# failure instead of a live one.
find "$STAGE" \( -name '._*' -o -name '.DS_Store' \) -type f -delete
JUNK=$(find "$STAGE" \( -name '._*' -o -name '.DS_Store' \) | wc -l | tr -d ' ')
[ "$JUNK" = "0" ] || { echo "ERROR: $JUNK AppleDouble/DS_Store files survived the purge in $STAGE" >&2; rm -rf "$STAGE"; exit 1; }
COPYFILE_DISABLE=1 tar czf /tmp/ui-bundle.tgz -C "$STAGE" . || { rm -rf "$STAGE"; exit 1; }
rm -rf "$STAGE"
echo "    $(du -h /tmp/ui-bundle.tgz | cut -f1) bundle"
echo "    $(tar tzf /tmp/ui-bundle.tgz | grep -c '\._' || true) AppleDouble entries in the tarball (must be 0)"

echo "==> pushing to ${SSH_USER}@${EIP}"
scp -i "$KEY_FILE" -o BatchMode=yes -q /tmp/ui-bundle.tgz "${SCRIPT_DIR}/ui/ui-route.caddy" \
    "${SSH_USER}@${EIP}:/tmp/" \
  || { echo "ERROR: scp failed (is port 22 reachable from this network? its egress IP roams)" >&2; exit 1; }

# The remote script reads $UI_SNIPPET_PATH, so the snippet has to be on the box first (done above)
# and the variable has to reach the non-login shell that `bash -s` starts.
if [ "$MODE" = "--revert" ]; then
  printf '%s\n' "$REMOTE" | ssh -i "$KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "${SSH_USER}@${EIP}" "UI_REVERT=1 UI_SNIPPET_PATH=/tmp/ui-route.caddy bash -s"
else
  printf '%s\n' "$REMOTE" | ssh -i "$KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "${SSH_USER}@${EIP}" "UI_SNIPPET_PATH=/tmp/ui-route.caddy TOKEN_LIST_SHA=${TL_SHA:-} UI_RETIRED='${RETIRED_UI_FILES[*]}' bash -s"
fi
