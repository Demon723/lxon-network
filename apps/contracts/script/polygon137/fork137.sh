#!/usr/bin/env bash
# Bring up a chain-137 fork for the addAttestor rehearsal and print the facts it must match.
set -uo pipefail
UPSTREAM="${UPSTREAM:-https://polygon-bor-rpc.publicnode.com}"
PORT="${PORT:-8547}"
F="http://127.0.0.1:$PORT"
PWX=0xD69fB341F35cadE285331797D7d35c5613D7Dfbe
PTL=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054

# foundry 1.8.4 takes --fork-block-number as a decimal integer only -- measured: passing the hex
# eth_blockNumber returns ("0x5bc5d7a") dies with "invalid digit found in string".
BN_HEX="$(cast rpc eth_blockNumber --rpc-url "$UPSTREAM" | tr -d '"')"
BN="$(python3 -c "print(int('${BN_HEX:-0x0}',16))")"
echo "upstream latest block: $BN ($BN_HEX)"
anvil --fork-url "$UPSTREAM" --fork-block-number "$BN" --fork-chain-id 137 --port "$PORT" \
  >/tmp/wlx137-att-anvil.log 2>&1 &
ANVIL=$!
for _ in $(seq 1 40); do
  cast rpc eth_chainId --rpc-url "$F" >/dev/null 2>&1 && break
  sleep 1
done
echo "anvil pid $ANVIL"
echo "fork chainId = $(cast rpc eth_chainId --rpc-url "$F" | tr -d '"')"
echo "fork block   = $(cast rpc eth_blockNumber --rpc-url "$F" | tr -d '"')"
echo "PWX code len = $(cast rpc eth_getCode "$PWX" latest --rpc-url "$F" | tr -d '\n' | wc -c)"
echo "PTL code len = $(cast rpc eth_getCode "$PTL" latest --rpc-url "$F" | tr -d '\n' | wc -c)"
echo "time of head = $(cast rpc eth_getBlockByNumber latest false --rpc-url "$F" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16), int(d["baseFeePerGas"],16))')"
