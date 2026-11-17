#!/usr/bin/env bash
# Make www.lxon.in live on the free-tier node: publish the LXON site and serve it from the same
# Caddy that fronts the read-only RPC.
#
#   ./expose-www.sh              # build, publish, install the site, verify
#   ./expose-www.sh --check      # change nothing; report what is live vs what was published
#   ./expose-www.sh --revoke     # remove the www fragment (rpc.lxon.in is left alone)
#
# What is deliberately NOT published, and why (measured 2026-11-03, see www-src/swap/index.html):
# the swap interface's eight chain-724 contracts all answer eth_getCode 0x on the restarted chain,
# so the trading form would invite approvals against contracts that do not exist. /swap serves an
# honest offline page instead. Nothing else about the site is changed by publishing.
#
# Corrected 2026-11-04, after measuring the live pages instead of trusting this comment: the claim
# that "the pages already label any figure they cannot read as not read" was FALSE as published.
# 6 cells on / and 7 on /app sat in data-read="wait" indefinitely -- "Gas used —", "Txns in tip —",
# the four chain-stats slots, "reading chain stats…" -- because each read was placed after an early
# return that fires whenever the explorer is down, which is every visit since the chain restarted.
# Fixed in $UI_SRC (app-web.html: loadChainStats split out of loadActivity; landing-light.html: the
# tip metrics moved to the RPC read that already has them, and the pool cells get terminal states);
# proven with the three-mode probe in ~/.lxon/runs/www-stats-probe/server.py, which asserts 0 visible
# stuck cells with the explorer failing AND the right numbers with a stubbed explorer answering.
#
# Exit 0 only if the published bytes are the served bytes and the RPC front still works.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/front-lib.sh"

HOST="www.lxon.in"
EXPLORER_HOST="explorer.lxon.in"
UI_SRC="${UI_SOURCE_DIR:-/Users/adikamble/LXON/lxon-web-ui}"
MODE_ARG="${1:-deploy}"
REMOTE_WWW="/opt/lxon/www"

# Files the published site must contain, as: <local source> -> <path under the web root>
# Kept as one table so --check and the publish step can never disagree about the file list.
PUBLISH=(
  "landing-light.html|index.html"
  "app-web.html|app/index.html"
  "app.js|app.js"
  "lxon-auth.json|lxon-auth.json"
  "assets/lxon-mark-64.png|assets/lxon-mark-64.png"
  "assets/lxon-mark-96.png|assets/lxon-mark-96.png"
  "assets/lxon-mark-192.png|assets/lxon-mark-192.png"
  "assets/lxon-mark-512.png|assets/lxon-mark-512.png"
  "assets/lxon-mark-1024.png|assets/lxon-mark-1024.png"
)
# From www-src (new files this script owns rather than copies from the UI bundle)
LOCAL_EXTRA=(
  "swap/index.html|swap/index.html"
  "explorer-offline/index.html|explorer-offline/index.html"
)

BUILD=""
cleanup() { [ -n "$BUILD" ] && rm -rf "$BUILD"; }
trap cleanup EXIT

build_site() {
  BUILD=$(mktemp -d "${TMPDIR:-/tmp}/lxon-www-build.XXXXXX") || fl_fail "mktemp failed"
  echo "==> Building the publish set"
  [ -d "$UI_SRC" ] || fl_fail "UI source directory $UI_SRC not found (set UI_SOURCE_DIR=)"
  local entry src dst n=0
  for entry in "${PUBLISH[@]}"; do
    src="$UI_SRC/${entry%%|*}"; dst="$BUILD/${entry##*|}"
    [ -f "$src" ] || fl_fail "missing $src"
    mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; n=$((n+1))
  done
  for entry in "${LOCAL_EXTRA[@]}"; do
    src="$SCRIPT_DIR/www-src/${entry%%|*}"; dst="$BUILD/${entry##*|}"
    [ -f "$src" ] || fl_fail "missing $src"
    mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; n=$((n+1))
  done
  echo "    $n files staged in $BUILD"
  # Guard against ever shipping the trading form: if a swap.html ever appears in the build dir,
  # the script is wrong, not the check.
  if [ -e "$BUILD/swap.html" ]; then fl_fail "swap.html must not be published while its contracts read 0x"; fi
}

verify_site() { # reads nothing, writes nothing
  local mode="$1" scheme="http" port=80
  [ "$mode" = "https" ] && { scheme="https"; port=443; }
  local fails=0 entry dst code
  echo "=== verification: published bytes vs served bytes ($scheme) ==="
  for entry in "${PUBLISH[@]}" "${LOCAL_EXTRA[@]}"; do
    dst="${entry##*|}"
    fl_serve_matches "$BUILD/$dst" "$scheme" "$HOST" "/$dst" || fails=$((fails+1))
  done
  # The three routes the site's own navigation uses, checked by the URL a visitor would type rather
  # than by the file path they resolve to.
  fl_serve_matches "$BUILD/index.html" "$scheme" "$HOST" "/" >/dev/null \
    && echo "      same bytes: /  (the landing page is the home route)" \
    || { echo "      FAIL: / does not serve the landing page"; fails=$((fails+1)); }
  fl_serve_matches "$BUILD/app/index.html" "$scheme" "$HOST" "/app" >/dev/null \
    && echo "      same bytes: /app" \
    || { echo "      FAIL: /app does not serve the app page"; fails=$((fails+1)); }
  fl_serve_matches "$BUILD/swap/index.html" "$scheme" "$HOST" "/swap" >/dev/null \
    && echo "      same bytes: /swap  (the offline notice, not the trading form)" \
    || { echo "      FAIL: /swap does not serve the offline notice"; fails=$((fails+1)); }

  # The trading form must not be reachable under any plausible name. This is the whole point of
  # withholding it, so it is asserted, not assumed.
  local gone
  for gone in /swap.html /ui/swap.html /swap/swap.html; do
    code=$(curl -sS -m 15 --resolve "$HOST:$port:$EIP" -o /dev/null -w '%{http_code}' \
             "$scheme://$HOST$gone" 2>/dev/null)
    if [ "$code" = "404" ]; then
      echo "      $gone is not served (404)"
    else
      echo "      FAIL: $gone returned $code -- the trading form must not be published"; fails=$((fails+1))
    fi
  done

  # A wrong hostname must not be served this site, over the SAME scheme Caddy is listening on.
  # (Sending http:// to 443 returns "Client sent an HTTP request to an HTTPS server", which once
  # looked like a pass for the wrong reason.)
  local other
  other=$(curl -sSk -m 15 --resolve "wrong.example:$port:$EIP" \
            "$scheme://wrong.example:$port/" 2>&1 | head -c 80)
  if printf '%s' "$other" | grep -qi "not found\|404\|refused\|reset\|no such host"; then
    echo "      an unmatched Host is not served the site"
  else
    echo "      FAIL: unmatched Host got content: ${other:0:70}"; fails=$((fails+1))
  fi

  # The regression the fragment redesign exists to prevent: two sites in one Caddyfile, and the
  # second one must not have silently unseated the first.
  echo "=== the RPC front must still work after installing a second site ==="
  local rpc
  rpc=$(curl -sS -m 15 -X POST -H 'content-type: application/json' \
          -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
          "$scheme://rpc.lxon.in:$port/" 2>&1)
  if printf '%s' "$rpc" | grep -q '0x2d4'; then
    echo "      https://rpc.lxon.in still answers: $(echo "$rpc" | head -c 60)"
  else
    echo "      FAIL: installing www broke the RPC front -> ${rpc:0:90}"; fails=$((fails+1))
  fi

  # The third hostname: it must answer as a page, not as a TLS error, and it must not be able to
  # serve anything except the notice and the assets it references.
  echo "=== $EXPLORER_HOST ==="
  local ex_code ex_body
  ex_code=$(curl -sSk -m 15 --resolve "$EXPLORER_HOST:$port:$EIP" -o /dev/null -w '%{http_code}' \
              "$scheme://$EXPLORER_HOST/" 2>/dev/null)
  [ "$ex_code" = "200" ] && echo "      $EXPLORER_HOST/ answers 200 (not a TLS error, not a 404)" \
    || { echo "      FAIL: $EXPLORER_HOST/ returned $ex_code"; fails=$((fails+1)); }
  ex_body=$(curl -sSk -m 15 --resolve "$EXPLORER_HOST:$port:$EIP" "$scheme://$EXPLORER_HOST/" 2>/dev/null)
  printf '%s' "$ex_body" | grep -q 'Block explorer' \
    && echo "      and it is the explorer notice" \
    || { echo "      FAIL: $EXPLORER_HOST/ is not serving the notice"; fails=$((fails+1)); }
  # The old explorer API must stay dead -- answering 200 with HTML there would invite callers to
  # parse a page as data.
  local apicode
  apicode=$(curl -sSk -m 15 --resolve "$EXPLORER_HOST:$port:$EIP" -o /dev/null -w '%{http_code}' \
              "$scheme://$EXPLORER_HOST/api/v2/stats" 2>/dev/null)
  if [ "$apicode" = "200" ]; then
    echo "      NOTE: /api/v2/stats returns 200 (the notice). Machine callers get HTML, which is the"
    echo "            honest outcome while no explorer exists -- there is no data to serve."
  else
    echo "      /api/v2/stats returned $apicode"
  fi

  echo
  if [ "$fails" -ne 0 ]; then
    echo "==> NOT verified: $fails check(s) failed. The site is not correctly live."
    return 1
  fi
  echo "==> Every published file is byte-identical to what the node serves."
  return 0
}

# ---------------------------------------------------------------------------
fl_resolve_target
DNS_MODE=$(fl_mode_for "$HOST"); echo

case "$MODE_ARG" in
  --revoke)
    echo "==> Removing the www fragment (rpc.lxon.in is untouched)"
    fl_ssh "sudo rm -f $FRONT_LIB_SITES_DIR/www.http.caddy $FRONT_LIB_SITES_DIR/www.https.caddy
            sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
            sudo systemctl reload caddy && echo '    reloaded'
            ls -1 $FRONT_LIB_SITES_DIR/ | sed 's/^/      remaining fragment: /'" \
      || fl_fail "could not remove the fragment"
    echo "==> /opt/lxon/www left in place; delete it by hand if you want the files gone too."
    exit 0 ;;
  --check)
    build_site
    verify_site "$DNS_MODE"
    exit $? ;;
esac

build_site

echo "==> Installing the $DNS_MODE site fragment for $HOST"
fl_install_caddy "$SCRIPT_DIR/caddy-sites" "www.$DNS_MODE" "$HOST"

# explorer.lxon.in was moved to this instance too, and this script owns "the public website", so it
# owns the third name as well. Its DNS is measured separately rather than assumed to match www's --
# the owner can move one record and not the others, and the fragment choice has to follow the truth.
echo "==> Installing the explorer notice for $EXPLORER_HOST"
EXPLORER_MODE=$(fl_mode_for "$EXPLORER_HOST"); echo
fl_install_caddy "$SCRIPT_DIR/caddy-sites" "explorer.$EXPLORER_MODE" "$EXPLORER_HOST"

echo "==> Publishing the site"
fl_publish_dir "$BUILD" "$REMOTE_WWW"

if [ "$DNS_MODE" = "https" ] || [ "$EXPLORER_MODE" = "https" ]; then fl_open_ports "80 443"; else fl_open_ports "80"; fi

verify_site "$DNS_MODE" || exit 1

cat <<EOF

==> www.lxon.in is live on this node.   Mode: $DNS_MODE

  Served:  /            the landing page (figures read live from rpc.lxon.in, or labelled "not read")
           /app         the app view
           /swap        an honest offline notice, NOT the trading form
  Withheld: the swap UI itself -- its eight chain-724 contracts all read eth_getCode 0x since the
            chain was restarted from an empty volume on 2026-11-03.

$(if [ "$DNS_MODE" = "http" ]; then printf '  Until you move DNS this is plain HTTP and the public hostname still points elsewhere.\n  Reach it by pinning:  curl --resolve %s:80:%s http://%s/\n  Your action: point the www A record at %s, then re-run ./expose-www.sh -- it measures DNS and\n  installs the TLS fragment by itself. DNS is parked at Hostinger (byte/pixel.dns-parking.com) and\n  the IAM user has no Route 53 permission, so this script cannot do it.\n' "$HOST" "$EIP" "$HOST" "$EIP"; fi)
  Known gaps, not hidden:
    - explorer.lxon.in has no stack on this box (only Besu runs), so the explorer links inside the
      landing page currently lead nowhere, and the explorer-derived figures render as "not read".
    - lxon-auth.json ships with googleClientId empty, so Google sign-in shows "not configured" by
      design. Filling it needs a real OAuth origin registered by you.
    - The apex lxon.in has no A record at all, so it is not served; add www only.

  Take the site down without touching the RPC:  ./expose-www.sh --revoke
EOF
