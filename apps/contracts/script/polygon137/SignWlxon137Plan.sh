#!/usr/bin/env bash
# Sign a Polygon-137 wLXONSecure/migration plan on the machine where the keystore lives, and hand back
# only signed transactions.
#
#   PLAN_DIR=/tmp/wlxon137-deploy KEYSTORE=/opt/lxon/keystores/137-deployer \
#   PASSWORD_FILE=/opt/lxon/secrets/137-deployer.pw bash script/polygon137/SignWlxon137Plan.sh
#
# This is the key-host half of the split (BroadcastWlxon137Signed.sh is the other half). It writes
# nothing to a chain: `cast mktx` signs and stops. Nothing it produces reveals the key -- a signature
# proves *who* signed, not *with what* -- which is why the launch machine never needs a shell on this
# one, and this one never needs to be reachable from the launch.
#
# It is the 137 sibling of script/v41/Sign137Plan.sh, and deliberately the same shape: same EIP-1559
# fee spelling (no --legacy), same four re-checks, same decode-every-signature-before-claiming-it, same
# refusal of a key on a command line. The one difference is what the batch is for -- deploys and wires
# wLXONSecure and the migration contract instead of the v4.1 bridge -- so the facts it re-checks are
# read from this ceremony's plan.json, and there is no seal() here to warn about.
#
# Rules it holds so a ceremony does not become a leak:
#   * KEYSTORE=/PASSWORD_FILE= only. PRIVATE_KEY= is refused: a key on a command line lands in shell
#     history and in the process table, and that is how a launch key gets published.
#   * every signature is decoded back and compared with the plan before it is claimed as signed.
#     Signing and certifying on one machine, with no second look, is a self-validating check.
#   * the plan's own numbers are re-measured against a node before any of them is authorised. A plan is
#     a document; the nonce it names is a fact that can have stopped being true.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="script/polygon137/lib/offline_plan1559.py"

PLAN_DIR="${PLAN_DIR:?usage: PLAN_DIR=<dir holding plan.json> KEYSTORE=... PASSWORD_FILE=... bash script/polygon137/SignWlxon137Plan.sh}"
export PLAN_DIR
[ -f "$PLAN_DIR/plan.json" ] || { echo "FATAL: no $PLAN_DIR/plan.json -- make it with PlanWlxon137.sh PLAN_DIR=$PLAN_DIR" >&2; exit 1; }
[ -z "${PRIVATE_KEY:-}" ] || { echo "FATAL: this script signs from KEYSTORE=/PASSWORD_FILE= only. A key in a command line is a leaked key." >&2; exit 1; }

if [ -d "${KEYSTORE:-}" ]; then
  ACCOUNT="${ACCOUNT:-$(ls -1 "$KEYSTORE" | head -1)}"
  KS_FILE="$KEYSTORE/$ACCOUNT"
else
  KS_FILE="${KEYSTORE:?FATAL: set KEYSTORE to a keystore file, or a directory holding one}"
fi
[ -f "$KS_FILE" ] || { echo "FATAL: keystore not found: $KS_FILE" >&2; exit 1; }
PW="${PASSWORD_FILE:?FATAL: set PASSWORD_FILE to a file holding the keystore password -- never the password itself}"
[ -f "$PW" ] || { echo "FATAL: password file not found: $PW" >&2; exit 1; }

RPC="$(python3 "$LIB" field rpc)"
CHAIN="$(python3 "$LIB" field chainId)"
FROM="$(python3 "$LIB" field from)"
MAXFEE="$(python3 "$LIB" field maxFeePerGasWei)"
PRIORITY="$(python3 "$LIB" field maxPriorityFeePerGasWei)"
NTX="$(python3 "$LIB" field txCount)"
START="$(python3 "$LIB" field startNonce)"
PHASE="$(python3 "$LIB" field phase)"
PWX="$(python3 "$LIB" field predictedWlxon)"
PM="$(python3 "$LIB" field predictedMigration)"
WINDOW="$(python3 "$LIB" field opensMigrationWindow)"
[ -n "$RPC" ] || { echo "FATAL: this plan names no rpc, so its facts cannot be re-measured. Re-plan." >&2; exit 1; }

echo "  plan: chain $CHAIN, phase ${PHASE:-?}, signer $FROM, $NTX transactions from nonce $START"
echo "        maxFee $MAXFEE / tip $PRIORITY wei, rpc $RPC"
if [ "$PHASE" = "deploy" ]; then
  echo "        predicts wLXONSecure $PWX and migration $PM"
fi
if [ "$WINDOW" = "True" ]; then
  echo "  NOTE: the last transaction of this batch opens the migration window. From the moment it lands,"
  echo "        holders can surrender legacy wLXON 1:1 against the reserve this contract holds, and the"
  echo "        ones who arrive after the reserve runs out revert. Confirm the reserve on chain before signing."
fi

# ---- the facts a plan can have lost since it was made ------------------------------------------
# Chain id, identity, nonce, and both fee numbers. The nonce is the one that ruins a launch quietly: a
# plan signed after any other transaction moved this key puts the two creates at addresses that are not
# the ones setNewToken names -- so the migration contract would be wired to a token that was never
# deployed, and the reserve would be paid into a contract nobody can use.
got_chain="$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$got_chain" ] || { echo "FATAL: $RPC did not answer eth_chainId" >&2; exit 1; }
[ "$(python3 -c "print(int('$got_chain',16))")" = "$CHAIN" ] \
  || { echo "FATAL: $RPC is chain $got_chain and this plan is for $CHAIN; a signature made for the wrong chain id can never land." >&2; exit 1; }

got_from="$(cast wallet address --keystore "$KS_FILE" --password-file "$PW" 2>&1 | grep -Eo '0x[0-9a-fA-F]{40}' | head -1 || true)"
[ -n "$got_from" ] || { echo "FATAL: could not read an address out of that keystore" >&2; exit 1; }
if [ "$(printf '%s' "$got_from" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$FROM" | tr 'A-Z' 'a-z')" ]; then
  echo "FATAL: this keystore signs as $got_from; the plan is for $FROM. Wrong key, or a plan from another ceremony." >&2; exit 1
fi

latest="$(cast rpc eth_getTransactionCount "$got_from" latest --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$latest" ] || { echo "FATAL: $RPC did not answer eth_getTransactionCount" >&2; exit 1; }
now="$(python3 -c "print(int('$latest',16))")"
if [ "$now" != "$START" ]; then
  echo "FATAL: $got_from is at nonce $now and this plan starts at $START."
  echo "       If a transaction moved since the plan was made, re-plan. Do not shift these nonces by"
  echo "       hand: the address both creates land on was decided by the plan's starting nonce."
  exit 1
fi

# EIP-1559 has two numbers to keep honest, and they are not interchangeable with a legacy gasPrice.
# maxFee below base+tip is a transaction that cannot be included at all; maxFee below what the node
# suggests for inclusion is a batch that sits in the mempool through the ceremony window.
sug="$(cast rpc eth_gasPrice --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
if [ -n "$sug" ] && [ "$MAXFEE" -lt "$(python3 -c "print(int('$sug',16))")" ]; then
  echo "FATAL: the plan's maxFee is $MAXFEE wei and $RPC now asks $sug for inclusion."
  echo "       Re-plan rather than signing a batch nobody will sweep." >&2; exit 1
fi
base="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC" 2>/dev/null | python3 -c 'import sys,json;b=json.load(sys.stdin);b=b.get("result",b);print(int(b.get("baseFeePerGas","0x0"),16))' 2>/dev/null || echo '')"
if [ -n "$base" ] && [ "$MAXFEE" -lt "$(( base + PRIORITY ))" ]; then
  echo "FATAL: base fee is $base and the tip $PRIORITY, so maxFee must be >= $(( base + PRIORITY )); the plan says $MAXFEE."
  echo "       A maxFee below base+tip is a transaction that cannot be included. Re-plan." >&2; exit 1
fi

# Gas money the batch can still spend. A deployer that cannot pay for its own batch half-signs a
# launch: the first lines land, the fourth runs out of balance, and the ceremony is stranded between
# two contracts with one wired to the other.
bal="$(cast rpc eth_getBalance "$got_from" latest --rpc-url "$RPC" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
bal="$(python3 -c "print(int('${bal:-0x0}',16))")"
TXS="$(python3 "$LIB" txs)"
# Summed and compared in python: awk's numbers are IEEE doubles, which lose the low digits of a wei
# amount, and bash's [ -gt ] is a C long, which overflows at all -- 18.7 POL, the balance the real 137
# deployer holds, is 1.87e19 wei and past 2^63. A guard that errors out is not a guard.
worst="$(printf '%s\n' "$TXS" | python3 -c 'import sys
print(sum(int(c[5]) * int(c[6]) for c in (l.split("\t") for l in sys.stdin if l.strip())))')"
if python3 -c "import sys;sys.exit(0 if int(sys.argv[1]) > int(sys.argv[2]) else 1)" "$worst" "$bal"; then
  echo "FATAL: this batch caps at $worst wei of POL and $got_from holds $bal."
  echo "       Nothing is signed. Fund the gas account and re-plan." >&2; exit 1
fi

OUT="${SIGNED_DIR:-$PLAN_DIR/signed}"
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null || true)" ]; then
  echo "FATAL: $OUT is not empty. Signing into a directory that already holds signatures risks mixing"
  echo "       two ceremonies -- point SIGNED_DIR at a new path." >&2; exit 1
fi
mkdir -p "$OUT"

# ---- sign, then check what was signed ----------------------------------------------------------
# A heredoc rather than `python3 ... | while`: a piped loop body runs in a subshell, so its `exit 1`
# would have exited the subshell and the script would have carried on signing the rest of the batch
# after the first failure.
n=0
while IFS="$(printf '\t')" read -r label nonce to value data gas maxfee priority; do
  [ -n "$label" ] || continue
  idx="$(printf '%02d' "$n")"
  f="$OUT/$idx-$label.raw.hex"
  # The payload goes to mktx exactly as the plan holds it. Re-encoding here would let a plan and its
  # signatures agree with each other while both disagreed with what the ceremony intended.
  # Every option before the positionals: `cast mktx --create <CODE>` makes --create a subcommand with a
  # *variadic* tail, so a flag written after it is consumed as a constructor argument -- measured on
  # Besu 726 as `error: unexpected argument --keystore found`.
  # EIP-1559: --gas-price carries the MAX FEE and --priority-gas-price the tip; NO --legacy. A legacy
  # signature here would be a transaction Polygon accepts with no priority fee to sweep it.
  MKOPTS=(--keystore "$KS_FILE" --password-file "$PW" --chain "$CHAIN"
          --gas-price "$maxfee" --priority-gas-price "$priority" --gas-limit "$gas" --nonce "$nonce")
  # The plan carries a `value` column and `offline_plan1559.py compare()` checks it, but until now mktx was
  # never told about it -- so a value-bearing step (a payable swapExactETHForTokens, which moves the POL in
  # the `value` field and nowhere in calldata) would have been signed as a 0-wei transfer. The verifier then
  # stops the run with "signed but does not match the plan", which is the safe half: nothing wrong is
  # published, and the ceremony dies at a launch. Passing --value only when it is non-zero keeps every
  # existing zero-value plan byte-identical.
  if [ "$value" != "0" ] && [ -n "$value" ]; then
    MKOPTS+=(--value "$value")
  fi
  if [ "$to" = "0x" ]; then
    raw="$(cast mktx "${MKOPTS[@]}" --create "$data" 2>&1)" \
      || { echo "FATAL: mktx refused $label: $(printf '%s' "$raw" | head -c 200)" >&2; exit 1; }
  else
    raw="$(cast mktx "${MKOPTS[@]}" "$to" "$data" 2>&1)" \
      || { echo "FATAL: mktx refused $label: $(printf '%s' "$raw" | head -c 200)" >&2; exit 1; }
  fi
  hexline="$(printf '%s\n' "$raw" | grep -Eo '[0-9a-fA-F]{100,}' | tail -1 || true)"
  [ -n "$hexline" ] || { echo "FATAL: mktx gave no raw transaction for $label; its output was: $(printf '%s' "$raw" | head -c 200)" >&2; exit 1; }
  printf '%s\n' "$hexline" > "$f"
  if ! chk="$(python3 "$LIB" verify "$f" "$nonce" "$to" "$value" "$data" "$gas" "$maxfee" "$priority" "$CHAIN" "$FROM")"; then
    rm -f "$f"
    echo "FATAL: $idx-$label was signed but does not match the plan: $chk" >&2
    echo "       That file is deleted. Stop here -- the rest of the batch would be inconsistent with it." >&2
    exit 1
  fi
  where="-> $to"
  [ "$to" = "0x" ] && where="CREATE"
  printf '  OK   %s-%s  nonce=%s  %s  gas=%s  sha256=%s\n' "$idx" "$label" "$nonce" "$where" "$gas" \
    "$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:12])" "$f")"
  n=$((n + 1))
done <<EOF
$TXS
EOF

echo
echo "Signed $n of $NTX transactions into $OUT"
echo "Hand over that directory plus the plan -- not the keystore, not the password file. A signed"
echo "transaction is already everything a broadcaster needs, and the pinned nonces make each one"
echo "usable exactly once: the moment nonce $START is mined, the rest of the batch is dead."
if [ "$WINDOW" = "True" ]; then
  echo "The last one opens the migration window; the one before it moves the reserve."
fi
echo "Next, from anywhere that can reach $RPC:"
echo "  PLAN_DIR=$PLAN_DIR SIGNED_DIR=$OUT bash script/polygon137/BroadcastWlxon137Signed.sh"
