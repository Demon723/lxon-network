#!/usr/bin/env bash
# Tiny JSON-RPC client that runs ON the node, INSIDE the compose network.
# Kept separate so enable-public-rpc.sh never has to nest three layers of quoting to post a
# JSON body through ssh.
#
#   ./rpcq.sh http://besu-rpc:8545 eth_blockNumber
#   ./rpcq.sh http://besu-sealer:8545 eth_syncing
#   ./rpcq.sh http://besu-rpc:8545 eth_getBlockByNumber latest false
#
# The docker run is not decoration: besu-rpc has no host port at all and the sealer is published
# on 127.0.0.1 only, so a curl from the host can reach neither by service name. Running the
# request from a container on lxon-evm_default is what makes http://besu-sealer:8545 resolve.
# The caddy image is reused as the curl carrier because it is already pulled on this instance.
set -euo pipefail
url="${1:?usage: rpcq.sh <rpc-url> <method> [params...]}"
method="${2:?missing method}"
shift 2
params=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")
body=$(printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}' "$method" "$params")
network="${LXON_NET:-lxon-evm_default}"
docker run --rm --network "$network" --entrypoint curl caddy:2 \
  -sf --max-time 10 -X POST -H 'content-type: application/json' --data "$body" "$url"
