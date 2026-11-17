#!/usr/bin/env bash
# Runs ON THE INSTANCE. Asserts the loopback half of the front actually works.
# Written as a file rather than a heredoc-inside-ssh so that no quoting layer can silently
# drop a check. Exit 0 only if every assertion passed.
set -uo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-rpc.lxon.in}"
SITES_DIR="${SITES_DIR:-/etc/caddy/sites-enabled}"
FAILED=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1  -> $2"; FAILED=$((FAILED + 1)); }

rpc() { # <json payload> -> response body (gateway on loopback)
  curl -sS -m 8 -X POST -H 'content-type: application/json' -d "$1" http://127.0.0.1:9545 2>&1
}

echo "  [unit] systemd"
S=$(systemctl is-active lxon-rpc-gateway 2>&1)
[ "$S" = "active" ] && ok "lxon-rpc-gateway is active" || bad "gateway not active" "$S"

E=$(systemctl is-enabled lxon-rpc-gateway 2>&1)
[ "$E" = "enabled" ] && ok "enabled at boot" || bad "not enabled at boot" "$E"

echo "  [gateway] behaviour"
R=$(rpc '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}')
case "$R" in *0x2d4*) ok "eth_chainId -> $R" ;; *) bad "eth_chainId" "$R" ;; esac

R=$(rpc '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["0x0",false]}')
case "$R" in *0x6c931dff*) ok "block 0 is the recovered genesis hash" ;; *) bad "block 0 wrong/unreadable" "$(echo "$R" | head -c 120)" ;; esac

R=$(rpc '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}')
case "$R" in *'"result":"0x'*) ok "eth_blockNumber -> $R" ;; *) bad "eth_blockNumber" "$R" ;; esac

# A write must be refused AND must not be a 200 that came back from Besu.
CODE=$(curl -sS -m 8 -o /tmp/w.out -w '%{http_code}' -X POST -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_sendRawTransaction","params":["0xdeadbeef"]}' \
        http://127.0.0.1:9545 2>&1)
BODY=$(head -c 120 /tmp/w.out 2>/dev/null); rm -f /tmp/w.out
if [ "$CODE" = "403" ] || [ "$CODE" = "401" ]; then
  ok "eth_sendRawTransaction refused with HTTP $CODE: $BODY"
else
  bad "eth_sendRawTransaction must be refused" "HTTP $CODE: $BODY"
fi

CODE=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"admin_peers","params":[]}' http://127.0.0.1:9545 2>&1)
[ "$CODE" = "403" ] && ok "admin_peers refused (HTTP 403)" || bad "admin_peers" "HTTP $CODE"

# default-deny, not the NEVER list: a method nobody named must still be refused
CODE=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"personal_importRawKey","params":["0x00","pw"]}' \
        http://127.0.0.1:9545 2>&1)
[ "$CODE" = "403" ] && ok "unlisted method refused by the allow-list (HTTP 403)" \
                    || bad "personal_importRawKey must be refused" "HTTP $CODE"

# a blocked method must not be able to ride inside an otherwise-valid batch
R=$(rpc '[{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]},{"jsonrpc":"2.0","id":2,"method":"eth_sendRawTransaction","params":["0xdead"]}]')
if printf '%s' "$R" | grep -q 'not available'; then
  ok "blocked element poisons the whole batch (no partial forward)"
else
  bad "batch with a blocked method must be refused" "$(printf '%s' "$R" | head -c 140)"
fi

# Caddy's health probe is a GET /; if that breaks the upstream is marked down and every request 502s
R=$(curl -sS -m 8 http://127.0.0.1:9545/ 2>&1)
case "$R" in *0x2d4*) ok "GET / answers (Caddy health_uri will pass)" ;; *) bad "GET / health probe" "$R" ;; esac

echo "  [isolation] what must NOT be listening"
if sudo ss -ltn | grep -qE '0\.0\.0\.0:8545|\[::\]:8545|\*:8545'; then
  bad "Besu 8545 is bound to a public interface" "$(sudo ss -ltn | grep 8545 | head -1)"
else
  ok "Besu 8545 is not public on the box"
fi
if ss -ltn | grep -qE '0\.0\.0\.0:9545'; then
  bad "the gateway itself is bound outside loopback" "$(ss -ltn | grep 9545 | head -1)"
else
  ok "gateway listens on 127.0.0.1 only (Caddy is the sole public door)"
fi

echo "  [caddy]"
C=$(systemctl is-active caddy 2>&1)
[ "$C" = "active" ] && ok "caddy is active" || bad "caddy" "$C"
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/tmp/cv.log 2>&1 \
  && ok "Caddyfile validates" || bad "Caddyfile invalid" "$(tail -3 /tmp/cv.log | tr '\n' ' ')"
rm -f /tmp/cv.log

# THE END-TO-END PATH: through Caddy with the public Host header, not just straight to the gateway.
# A gateway-only test once passed while every public request 403'd, because Besu rejects a Host it
# does not allow-list and the direct tests used a localhost Host.
#
# In TLS mode port 80 only REDIRECTS, so reading the body there comes back empty and looks like a
# failure (it did, on 2026-11-03). Probe whichever port actually serves.
if sudo grep -q '^rpc\.lxon\.in {' $SITES_DIR/*.caddy 2>/dev/null; then
  PROBE="https"; PROBE_PORT=443
else
  PROBE="http";  PROBE_PORT=80
fi
# --resolve, not -H Host: with TLS the SNI comes from the URL host, and curl would otherwise ask
# Caddy for a certificate covering "127.0.0.1" -- which it rightly refuses, and the check then
# reports an SSL alert instead of the site's behaviour.
PROBE_URL="$PROBE://$EXPECTED_HOST:$PROBE_PORT/"
RESOLVE="--resolve $EXPECTED_HOST:$PROBE_PORT:127.0.0.1"
echo "  [proxied] probing $PROBE_URL pinned to loopback (TLS mode: $( [ "$PROBE" = https ] && echo yes || echo no ))"

R=$(curl -sSk -m 8 $RESOLVE -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "$PROBE_URL" 2>&1)
case "$R" in *0x2d4*) ok "Caddy -> gateway -> Besu answers with the public hostname" ;;
                  *) bad "proxied path for $EXPECTED_HOST" "$(printf '%s' "$R" | head -c 140)" ;; esac

R=$(curl -sSk -m 8 $RESOLVE -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_sendRawTransaction","params":["0xdeadbeef"]}' \
      "$PROBE_URL" 2>&1)
case "$R" in *"not available"*) ok "write refused on the proxied path too" ;;
                            *) bad "proxied write must be refused by the gateway" "$(printf '%s' "$R" | head -c 140)" ;; esac

R=$(curl -sSk -m 8 $RESOLVE -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{"fromBlock":"0x0","toBlock":"0x100000"}]}' \
      "$PROBE_URL" 2>&1)
[ "$R" = "400" ] && ok "the 1M-block eth_getLogs range is refused on the proxied path (400)" \
                 || bad "over-wide eth_getLogs must be 400" "$R"

# a request with the wrong Host must not reach the RPC at all
R=$(curl -sSk -m 8 --resolve "wrong.example:$PROBE_PORT:127.0.0.1" -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "https://wrong.example:$PROBE_PORT/" 2>&1)
case "$R" in *0x2d4*) bad "no-matching-Host request was served the RPC" "$R" ;;
                   *) ok "unmatched Host does not get the RPC" ;; esac

echo
if [ "$FAILED" -ne 0 ]; then
  echo "  $FAILED loopback check(s) FAILED"
  exit 1
fi
echo "  all loopback checks passed"
