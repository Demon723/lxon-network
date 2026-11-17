#!/usr/bin/env bash
# Print (and, with --save, persist) a node's enode URL as Besu itself reports it.
# Usage: ./capture-enode.sh [container] [--save]     container default: lxon-725-node-1
# The node id comes from Besu's own log line; the host part is the IPv4 Docker gave that
# container, because Besu only accepts an IP literal in a bootnode URL (see below).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="lxon-725-node-1"; SAVE=0
for a in "$@"; do
  case "$a" in
    --save) SAVE=1 ;;
    *) CONTAINER="$a" ;;
  esac
done
LOGS="$(docker logs "$CONTAINER" 2>&1 || true)"

# Measured against hyperledger/besu:26.10.0 (throwaway container, chainId 799, 2026-10-21):
#   DefaultP2PNetwork | Enode URL enode://<128 hex, NO 04 prefix>@127.0.0.1:30303
#   KeyPairUtil       | Loaded public key 0x<128 hex> from /key/key.priv
# The p2p line is authoritative; the key line is the fallback for a node whose p2p layer
# has not logged yet. Neither carries a 04 prefix, so none is added here.
ID="$(printf '%s\n' "$LOGS" | grep -oE 'enode://[0-9a-f]{128}' | head -1 | sed 's|enode://||' || true)"
[ -n "$ID" ] || ID="$(printf '%s\n' "$LOGS" | grep -oE 'Loaded public key 0x[0-9a-f]{128}' | head -1 | sed 's/.*0x//' || true)"
[ -n "$ID" ] || { echo "no node id in $CONTAINER logs yet; wait for it to finish starting" >&2; exit 1; }

# The host part must be an IPv4 literal, not the container name. Measured on
# hyperledger/besu:26.10.0 with real containers on 2026-10-22: Besu parses --bootnodes with
# its own EnodeURL validator and aborts on a DNS name with
#   Invalid bootnode: '...@lxon-725-node-1:30303'. Error: ... Invalid ip address.
# so every peer crash-loops at exit 2 even though Docker's embedded DNS *would* have resolved
# the name. The URL therefore uses the address Docker actually gave the container, read from
# Docker itself rather than guessed, and docker-compose.725.yml pins node-1 to a static
# address on a fixed subnet so the value persisted here cannot drift between bring-ups.
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
[ -n "$IP" ] || { echo "no IPv4 address for $CONTAINER on its docker network; is it running?" >&2; exit 1; }

# Port 30303 = the in-container p2p port (Besu's default), not a host-mapped port: peers reach
# each other over the compose network. 127.0.0.1 in Besu's own log line is its local view and
# is useless to a peer, so it is deliberately not reused.
ENODE="enode://${ID}@${IP}:30303"
echo "$ENODE"
if [ "$SAVE" = 1 ]; then printf '%s\n' "$ENODE" > "$HERE/enode-1.txt"; fi
