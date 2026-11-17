#!/usr/bin/env bash
# Put a read-only public front on chain 724:  rpc.lxon.in -> Caddy -> rpc-gateway.py -> Besu.
#
# What is exposed and what is not:
#   EXPOSED  80 (and 443 once DNS points here), serving only the gateway's allow-list.
#   NOT      Besu's 8545/8546 stay on 127.0.0.1 and the security group has no rule for them, so
#            nothing can reach Besu directly. eth_sendRawTransaction is refused by the gateway
#            before forwarding, so this endpoint cannot broadcast a transaction.
#
# The front is chosen by MEASURING DNS on every run. rpc.lxon.in resolves to this instance ->
# TLS; anywhere else -> interim plain HTTP, because Let's Encrypt validates the hostname and cannot
# issue while the A record points at the dead EIP. Re-run after moving DNS and it swaps itself.
#
#   ./expose-rpc.sh              # install / re-converge
#   ./expose-rpc.sh --revoke     # close the ports and disable the gateway
#
# Exit code 0 only when every check it ran passed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/front-lib.sh"

HOST="rpc.lxon.in"
MODE="${1:-deploy}"

fl_resolve_target

if [ "$MODE" = "--revoke" ]; then
  echo "==> Taking the RPC front down (Besu and the sealer are not touched)"
  fl_ssh 'sudo systemctl disable --now lxon-rpc-gateway 2>/dev/null && echo "    gateway stopped" \
          || echo "    gateway was not running"' \
    || echo "    WARN: could not reach the box; the gateway may still listen on loopback"
  fl_ssh "sudo rm -f $FRONT_LIB_SITES_DIR/rpc.http.caddy $FRONT_LIB_SITES_DIR/rpc.https.caddy
          sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && \
          sudo systemctl reload caddy && echo '    caddy reloaded without the rpc fragment' || echo '    WARN: reload skipped'"
  for port in 80 443; do
    if aws ec2 revoke-security-group-ingress --region "$FRONT_LIB_REGION" --group-id "$SG_ID" \
         --protocol tcp --port "$port" --cidr 0.0.0.0/0 >/dev/null 2>&1; then
      echo "    revoked $port"
    else
      echo "    $port was not open"
    fi
  done
  echo "==> The www fragment, if installed, is still serving. The chain keeps sealing privately."
  exit 0
fi

DNS_MODE=$(fl_mode_for "$HOST"); echo

echo "==> Installing the gateway"
fl_ssh 'mkdir -p /opt/lxon/staging' || fl_fail "SSH to $EIP failed -- nothing was installed"
fl_scp "$SCRIPT_DIR/rpc-gateway.py" "$SCRIPT_DIR/systemd/lxon-rpc-gateway.service" \
       "$SCRIPT_DIR/install-rpc-gateway.sh" "$SCRIPT_DIR/verify-rpc-front.sh" \
       "$FRONT_LIB_SSH_USER@$EIP:/opt/lxon/staging/" \
  || fl_fail "scp failed -- nothing was installed"
# The install logic lives in a file that runs on the box, not in a quoted ssh argument.
fl_ssh 'bash /opt/lxon/staging/install-rpc-gateway.sh' \
  || fl_fail "gateway install failed -- no ports were opened"

fl_install_caddy "$SCRIPT_DIR/caddy-sites" "rpc.$DNS_MODE" "$HOST"

if [ "$DNS_MODE" = "https" ]; then fl_open_ports "80 443"; else fl_open_ports "80"; fi

echo
echo "=== verification (loopback, on the box) ==="
fl_ssh 'bash /opt/lxon/staging/verify-rpc-front.sh'
LOOPBACK_RC=$?

echo
echo "=== verification (from out here) ==="
FAILS=0
runcase() {
  local label="$1" expect="$2" cmd="$3" out
  out=$(bash -c "$cmd" 2>&1 | head -c 200)
  if printf '%s' "$out" | grep -Eq "$expect"; then
    echo "  PASS  $label -> ${out:0:110}"
  else
    echo "  FAIL  $label -> ${out:0:140}   (expected /$expect/)"
    FAILS=$((FAILS + 1))
  fi
}
runcase "Besu 8545 unreachable from outside" 'closed|refused|timed out|succeeded: 0' \
  "nc -z -G 6 $EIP 8545 2>&1 && echo 'OPEN-WRONG' || echo closed"

if [ "$DNS_MODE" = "https" ]; then
  runcase "443 reachable" 'open|succeeded' "nc -z -G 8 $EIP 443 2>&1 && echo open || echo closed"
  # ACME has to finish before the first TLS handshake can succeed; give it a bounded window rather
  # than failing on a race or pretending it is instant.
  fl_wait 90 "certificate issued and TLS answers for $HOST" \
    "curl -sS -m 15 --resolve $HOST:443:$EIP -o /dev/null https://$HOST/" || true
  runcase "https://$HOST returns the chain id" '0x2d4' \
    "curl -sS -m 20 -X POST -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}' https://$HOST"
  runcase "the certificate is Let's Encrypt, not Caddy's local CA" "Let's Encrypt|R3|R4|E5|E6" \
    "echo | openssl s_client -connect $EIP:443 -servername $HOST 2>/dev/null | openssl x509 -noout -issuer -subject"
else
  runcase "80 reachable" 'open|succeeded' "nc -z -G 8 $EIP 80 2>&1 && echo open || echo closed"
  runcase "HTTP via the public IP answers as $HOST" '0x2d4' \
    "curl -sS -m 20 --resolve $HOST:80:$EIP -X POST -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}' http://$HOST"
fi

# Chain-length independent, and asserted in BOTH directions. The first version asked for
# fromBlock=0..latest on a ~1,200-block chain against a 5,000-block cap -- a check that cannot fail,
# which is the pattern I keep being bitten by. A 1M-block range is over the cap whatever the head is,
# and the small range proves the cap is not simply blocking eth_getLogs.
if [ "$DNS_MODE" = "https" ]; then
  BASE="https://$HOST"; RESOLVE=""
else
  BASE="http://$HOST"; RESOLVE="--resolve $HOST:80:$EIP"
fi
runcase "a 1M-block eth_getLogs range is refused (400)" '^400$' \
  "curl -sS -m 20 $RESOLVE -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x0\",\"toBlock\":\"0x100000\"}]}' $BASE"
runcase "a small eth_getLogs range is still served (200)" '^200$' \
  "curl -sS -m 20 $RESOLVE -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x0\",\"toBlock\":\"0x64\"}]}' $BASE"
runcase "a write is refused over the public path (403)" '^403$' \
  "curl -sS -m 20 $RESOLVE -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_sendRawTransaction\",\"params\":[\"0xdeadbeef\"]}' $BASE"

TOTAL=$FAILS
[ $LOOPBACK_RC -ne 0 ] && TOTAL=$((TOTAL + 1))
echo
if [ "$TOTAL" -ne 0 ]; then
  echo "==> NOT verified: $TOTAL check group(s) failed. Do not treat this endpoint as working."
  echo "    Close the public ports with:  ./expose-rpc.sh --revoke"
  exit 1
fi

cat <<EOF
==> RPC front is up and every check passed.   Mode: $DNS_MODE

  Chain 724 is publicly readable through the allow-list gateway with a per-client budget and a
  bound on eth_getLogs ranges. Besu is loopback-only and writes are refused at the gateway.

$(if [ "$DNS_MODE" = "http" ]; then printf '  INTERIM ONLY -- plain HTTP.\n  %s resolves elsewhere, so no certificate can be issued.\n  Your action: point the A record at %s and re-run ./expose-rpc.sh; it detects the change and\n  swaps in the TLS fragment by itself.\n' "$HOST" "$EIP"; fi)
  Read it:
    curl -s$( [ "$DNS_MODE" = "http" ] && printf " --resolve %s:80:%s" "$HOST" "$EIP" ) \\
      -X POST -H 'content-type: application/json' \\
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \\
      $DNS_MODE://$HOST

  Take it back down:  ./expose-rpc.sh --revoke
EOF
