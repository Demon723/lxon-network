#!/usr/bin/env bash
# Rebuild the chain-724 genesis with a DIFFERENT QBFT validator, and tell you the block-0
# hash that new genesis will produce -- before anything is deployed.
#
#   ./RotateSealerGenesis.sh 0xYOURNEWVALIDATORADDRESS
#
# Why this exists: QBFT takes its validator set from genesis extraData, so rotating the sealer
# identity is not a config change -- it is a new genesis, hence a new block 0. Every downstream
# check (verify.sh, the README, any explorer or bridge doc) quotes a block-0 hash, so the number
# has to be computed here rather than discovered after the box is already sealing.
#
# The script refuses to emit anything unless two controls pass:
#   1. re-encoding the CURRENT genesis reproduces 0x6c931dff… as recorded by the live node
#      in the 2026-11-02 migration bundle (and, separately, Polygon block 0 matches its RPC);
#   2. rebuilding extraData with the *unchanged* validator returns the original 60 bytes.
# A tool that only ever prints a plausible hash is worse than no tool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="${SCRIPT_DIR}/genesis/genesis.qbft.json"
EXPECTED_SHA="a779acefd0014caf9cfa50d93151bc1d2cd3b07c22c3d16952ec0917282bca20"
BLOCK0_JSON="${BLOCK0_JSON:-/tmp/block0.json}"
NEWVALIDATOR="${1:-}"

[ -n "$NEWVALIDATOR" ] || { echo "usage: $0 0x<40-hex validator address>" >&2; exit 2; }
[[ "$NEWVALIDATOR" =~ ^0[xX][0-9a-fA-F]{40}$ ]] || { echo "ERROR: need 0x + 40 hex, got '$NEWVALIDATOR'" >&2; exit 2; }
if [[ "$NEWVALIDATOR" =~ ^0[xX]0{40}$ ]]; then
  echo "ERROR: the zero address cannot be a QBFT validator." >&2; exit 2
fi

GOT_SHA=$(shasum -a 256 "$GEN" | awk '{print $1}')
[ "$GOT_SHA" = "$EXPECTED_SHA" ] || {
  echo "ERROR: base genesis is not the recovered production file (sha $GOT_SHA)." >&2; exit 1; }
[ -f "$BLOCK0_JSON" ] || {
  echo "ERROR: $BLOCK0_JSON missing. It is the block-0 header recorded in" >&2
  echo "       ~/.lxon/migration/20261102T002439Z/inventory.txt -- without that anchor the" >&2
  echo "       encoder cannot be validated, so no hash printed here would mean anything:" >&2
  echo "       grep -o '{\"jsonrpc.*}}' ~/.lxon/migration/20261102T002439Z/inventory.txt | head -1 > $BLOCK0_JSON" >&2
  exit 1; }

OUT="${SCRIPT_DIR}/genesis/genesis.qbft.sealer-${NEWVALIDATOR: -8}.json"

echo "==> Controls"
python3 "${SCRIPT_DIR}/genesis_rotate.py" "$GEN" --control "$BLOCK0_JSON"

echo
echo "==> Rotation"
python3 "${SCRIPT_DIR}/genesis_rotate.py" "$GEN" --control "$BLOCK0_JSON" \
  --set-validator "$NEWVALIDATOR" --write "$OUT"

echo
echo "==> Written: $OUT"
echo "    sha256   : $(shasum -a 256 "$OUT" | awk '{print $1}')"
cat <<EOF

Next, if you want this chain instead of the original identity:

  1. Deploy with the rotated genesis, carrying the new hash forward so verify.sh has a
     real expectation instead of the old chain's:
       EXPECTED_BLOCK0=<NEW block-0 hash printed above> GENESIS_FILE=$OUT ./deploy.sh

  2. ./verify.sh with the same EXPECTED_BLOCK0 exported, or it will correctly report the
     mismatch against the 0x6c931dff… it was written for.

  3. The node must then be sealed by the key whose address is $NEWVALIDATOR. If you have not
     run NewSealerKeyOnInstance.sh yet, this genesis is ahead of the key and the node will
     produce nothing: generate first, rotate second.

  4. Remember what this costs: the genesis alloc is unchanged (still one funded account,
     0xFaE699d2…), but the chain is no longer identifiable as the old 724 by block 0. Nothing
     on Polygon 137 could reach it either way -- that lane is sealed against
     0x9B15fEe9…, which no longer exists -- so this is a naming/continuity choice, not a
     bridge choice.
EOF
