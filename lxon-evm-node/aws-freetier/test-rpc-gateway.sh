#!/usr/bin/env bash
# Exercise rpc-gateway.py against the live chain via an SSH tunnel, before it is deployed.
# Every case asserts a specific outcome; the negatives matter more than the positives, because a
# filter that cannot say no is decoration.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EIP="${EIP:-13.61.55.231}"
KEY="${KEY:-$HOME/.ssh/lxon-eu-north-1.pem}"
TPORT="${TPORT:-18545}"
GPORT="${GPORT:-19545}"
GW="$HERE/rpc-gateway.py"

fails=0
check() { # label expected-substring actual
  # grep -E: a bare `|` is alternation. Without -E the pattern "a|b" is a literal string and the
  # case silently never matches -- which read as a gateway failure when the gateway had refused
  # the smuggled batch exactly as intended.
  if printf '%s' "$3" | grep -Eq -- "$2"; then
    printf '  ok    %-42s %s\n' "$1" "$(printf '%s' "$3" | head -c 70)"
  else
    printf '  FAIL  %-42s wanted %s, got: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 90)"
    fails=$((fails+1))
  fi
}

echo "=== prerequisites ==="
[ -f "$KEY" ] || { echo "missing $KEY"; exit 1; }
lsof -nP -iTCP:"$TPORT" -sTCP:LISTEN >/dev/null 2>&1 && { echo "tunnel port $TPORT busy"; exit 1; }
lsof -nP -iTCP:"$GPORT" -sTCP:LISTEN >/dev/null 2>&1 && { echo "gateway port $GPORT busy"; exit 1; }

echo "=== start tunnel to $EIP ==="
ssh -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes \
    -n -N -L "127.0.0.1:${TPORT}:127.0.0.1:8545" "ubuntu@${EIP}" &
TUN=$!
for i in $(seq 1 20); do
  curl -sS -m 3 -X POST -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "http://127.0.0.1:$TPORT" >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -sS -m 3 -X POST -H 'content-type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "http://127.0.0.1:$TPORT" >/dev/null 2>&1; then
  echo "tunnel did not come up"; kill $TUN 2>/dev/null; exit 1
fi
echo "  tunnel up on $TPORT"

echo "=== start gateway (upstream = tunnel) ==="
GWAY_UPSTREAM_PORT="$TPORT" GWAY_LISTEN_PORT="$GPORT" python3 "$GW" >/tmp/gway.log 2>&1 &
GW_PID=$!
# Probe generously: a round trip through an SSH tunnel to eu-north-1 measured 0.4-1.7s, so a 2s
# timeout made a working gateway look dead. A readiness check that flakes out is a false negative
# waiting to send someone debugging the wrong thing.
for i in $(seq 1 30); do
  curl -sS -m 10 "http://127.0.0.1:$GPORT" >/dev/null 2>&1 && break; sleep 1
done
if ! curl -sS -m 10 "http://127.0.0.1:$GPORT" >/dev/null 2>&1; then
  echo "  gateway did not start; log:"; cat /tmp/gway.log; kill $TUN $GW_PID 2>/dev/null; exit 1
fi
echo "  gateway up on $GPORT"

U="http://127.0.0.1:$GPORT"
post() { curl -sS -m 25 -X POST -H 'content-type: application/json' -d "$1" "$U" 2>&1; }

echo
echo "=== POSITIVE: read methods must pass through to the real chain ==="
check "eth_chainId reaches Besu (0x2d4)"      '0x2d4'   "$(post '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}')"
check "eth_blockNumber returns a hex height"  '"result":"0x' "$(post '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}')"
B0HASH=$(post '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["0x0",false]}')
check "block 0 is the recovered chain (0x6c931dff)" '6c931dff' "$B0HASH"
check "eth_getCode of the genesis EOA works"  '"result":"0x"' "$(post '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["0xfae699d2848957c7c3be67d8c90f0e456419cada","latest"]}')"
check "GET liveness endpoint answers"         '0x2d4'   "$(curl -sS -m 8 "$U" 2>&1)"

echo
echo "=== NEGATIVE: writes and consensus methods must be refused, never forwarded ==="
check "eth_sendRawTransaction refused"        'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":2,"method":"eth_sendRawTransaction","params":["0xdeadbeef"]}')"
check "personal_sign refused"                 'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":3,"method":"personal_sign","params":["0x6869","0x0"]}')"
check "admin_peers refused"                   'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":4,"method":"admin_peers","params":[]}')"
check "qbft_proposeValidatorVote refused"     'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":5,"method":"qbft_proposeValidatorVote","params":["0x0",true]}')"
check "debug_traceTransaction refused"        'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":6,"method":"debug_traceTransaction","params":["0x0"]}')"
check "arbitrary unknown method refused"      'not available on the public read-only' \
  "$(post '{"jsonrpc":"2.0","id":7,"method":"eth_doSomethingNew","params":[]}')"

echo
echo "=== BYPASS ATTEMPTS: the cases a string-matching filter would miss ==="
check "blocked method smuggled inside a batch" 'batch element|not available' \
  "$(post '[{"jsonrpc":"2.0","id":8,"method":"eth_chainId","params":[]},{"jsonrpc":"2.0","id":9,"method":"eth_sendRawTransaction","params":["0xdead"]}]')"
check "method name with odd whitespace refused" 'not available' \
  "$(post '{"jsonrpc":"2.0","id":10,"method":" eth_sendRawTransaction","params":[]}')"
check "non-JSON body refused"                  'not JSON' "$(printf 'x' > /tmp/np; curl -sS -m 8 -X POST -H 'content-type: application/json' --data-binary @/tmp/np "$U")"
check "missing method refused"                 'not available' \
  "$(post '{"jsonrpc":"2.0","id":12}')"
python3 -c 'pad = "A" * 2000000
print("{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"eth_chainId\",\"params\":[\"" + pad + "\"]}")' > /tmp/big.json
check "oversized body refused"           'over|too large' \
  "$(curl -sS -m 30 -X POST -H 'content-type: application/json' --data-binary @/tmp/big.json "$U")"
check "empty body refused"                     'empty body' "$(post '')"

echo
echo "=== the refusal must be real: nothing reached Besu for the write ==="
# If filtering were bypassed, a bogus raw tx would come back with a Besu validation error
# ("invalid transaction"/"insufficient funds"), not our -32601. Asserting absence of that text
# is what proves the request never went upstream.
check "no Besu validation error leaked (proof it was not forwarded)" -32601 \
  "$(post '{"jsonrpc":"2.0","id":14,"method":"eth_sendRawTransaction","params":["0xf86c"]}')"

echo
echo "=== gateway counters ==="
tail -3 /tmp/gway.log

kill $TUN $GW_PID 2>/dev/null
wait $TUN 2>/dev/null; wait $GW_PID 2>/dev/null
rm -f /tmp/np /tmp/big.json

echo
if [ "$fails" = 0 ]; then
  echo "==> ALL GATEWAY CASES PASS. Safe to deploy as the public front."
else
  echo "==> $fails CASE(S) FAILED. Do not deploy until fixed."
fi
exit "$fails"
