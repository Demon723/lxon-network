#!/usr/bin/env bash
# Plan ONE direct ADMIN_ROLE call on Polygon 137 -- no timelock, because some addresses in this
# deployment are not timelocked -- and hand the result to the same sign/broadcast halves as every other
# 137 ceremony.
#
#   PHASE=setNewToken PLAN_DIR=/tmp/x DEPLOYER=0x… ADMIN_ARGS=0x… WLXON_I_ACCEPT_MAINNET_RISK=1 \
#   bash script/polygon137/PlanAdminCall137.sh
#
#   # a stop button takes no argument, so name the signature and pass ADMIN_ARGS empty:
#   PHASE=endMigration ADMIN_SIG='endMigration()' ADMIN_ARGS='' PLAN_DIR=/tmp/y DEPLOYER=0x… \
#   ADMIN_TARGET=0x642Af10C… WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh
#
# Why this exists separately from PlanAttestor137.sh: that planner is the timelock ceremony and it dies
# when ADMIN_ROLE does NOT belong to a timelock, which is the right behaviour for wLXONSecure and the
# wrong behaviour for PolygonWLXONMigration. Measured on chain 137 (2026-10-27):
#
#   wLXONSecure   0xD69fB341…  ADMIN_ROLE -> 0x5Bfc2fD8… (TimelockController, minDelay 172800)
#   migration     0x642Af10C…  ADMIN_ROLE -> 0x2a8Ca01C… (the deployer key, DEFAULT_ADMIN too)
#
# because PolygonWLXONMigration's constructor does `_grantRole(ADMIN_ROLE, msg.sender)` while wLXONSecure's
# passes its admin to constructor argument 6. So setNewToken / startMigration / pauseMigration are one
# signature away, immediately -- the exact shape the runbook's WLXON_I_ACCEPT_ADMIN_IS_DEPLOYER guard was
# written to catch on the other contract. This script does not hide that: it prints it into plan.json as
# `custodyMode`, so a launch record shows which key authorised a live change instead of implying a delay
# that never happened.
#
# Same rules as every other planner here: no key in sight (PRIVATE_KEY= / KEYSTORE= refused), the chain's
# answers are re-measured rather than trusted from notes, and the signature must exist in the compiled
# artifact of the contract named.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_LIB="script/polygon137/lib/plan137.py"

die() { echo "FATAL: $*" >&2; [ -n "${CREATED_PLAN_DIR:-}" ] && [ "$CREATED_PLAN_DIR" = "${PLAN_DIR:-}" ] \
  && echo "       ($PLAN_DIR holds whatever this run wrote before it stopped -- use a new directory next time)" >&2
  exit 1; }
say() { printf '  %s\n' "$*"; }
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
has_code() { local c; c="$(cast rpc eth_getCode "$1" latest --rpc-url "$RPC_137" 2>/dev/null | tr -d '"' || true)"
             [ -n "$c" ] && [ "$c" != "0x" ]; }
rd() { cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_137" 2>/dev/null | head -1; }
addr_guard() {
  printf '%s' "$1" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "$2=$1 is not a 20-byte address"
  [ "$(lc "$1")" != "0x0000000000000000000000000000000000000000" ] || die "$2 is the zero address"
  case "$(lc "$1")" in
    0x00000000000000000000000000000000000000*|0x11111111111111111111111111111111111111*|0xdead0000000000000000000000000000000000*)
      die "$2=$1 looks like a placeholder. Nothing is planned against a placeholder." ;;
  esac
}

PHASE="${PHASE:?usage: PHASE=<function name, e.g. setNewToken> PLAN_DIR=<new dir> DEPLOYER=0x… ADMIN_ARGS=0x…}"
DEPLOYER="${DEPLOYER:?usage: DEPLOYER=<the address that must already hold ADMIN_ROLE on the target>}"
PLAN_DIR="${PLAN_DIR:?usage: PLAN_DIR=<new dir>}"
TARGET="${ADMIN_TARGET:?usage: ADMIN_TARGET=<the contract whose ADMIN_ROLE function is being called>}"
# A no-argument admin call is a legal call, and until 2026-10-28 it was unplannable here: this line
# required ADMIN_ARGS and the next hard-coded one argument, so the only shape the tool could build was
# `PHASE(address)`. endMigration(), pauseMigration() and unpauseMigration() take nothing -- they are the
# contract's only stop buttons -- which meant the documented "close the window" owner option had no plan
# / sign / broadcast route and would have been done by typing `cast send` at mainnet with no preflight.
ADMIN_ARGS="${ADMIN_ARGS-}"
if [ -z "$ADMIN_ARGS" ] && [ -z "${ADMIN_SIG:-}" ]; then
  die "ADMIN_ARGS is empty and no ADMIN_SIG was given, so there is nothing to encode. Either pass the arguments for $PHASE, or name the no-argument call explicitly: ADMIN_SIG='$PHASE()' ADMIN_ARGS='' (the empty ADMIN_ARGS is what tells this script you mean a zero-argument function, not that you forgot the argument)."
fi
if [ -n "${ADMIN_SIG:-}" ]; then SIG="$ADMIN_SIG"
elif [ -n "$ADMIN_ARGS" ]; then SIG="$PHASE(address)"
else SIG="$PHASE()"; fi
ARTIFACT="${ADMIN_ARTIFACT:-PolygonWLXONMigration}"
RPC_137="${RPC_137:-https://polygon-bor-rpc.publicnode.com}"
EXPECT_CHAIN="${WLXON_EXPECT_CHAIN_ID:-137}"

[ -z "${PRIVATE_KEY:-}" ] || die "PLAN mode needs no key. PRIVATE_KEY= is refused here on purpose -- unset it."
[ -z "${KEYSTORE:-}" ] || die "PLAN mode needs no keystore; SignWlxon137Plan.sh is the script that uses one."
[ -z "${PASSWORD_FILE:-}" ] || die "PLAN mode needs no password file either."
addr_guard "$DEPLOYER" DEPLOYER
addr_guard "$TARGET" ADMIN_TARGET

got_chain="$(cast rpc eth_chainId --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$got_chain" ] || die "$RPC_137 did not answer eth_chainId"
CHAIN="$(python3 -c "print(int('$got_chain',16))")"
[ "$CHAIN" = "$EXPECT_CHAIN" ] || die "$RPC_137 reports chain $CHAIN and this run is guarded for $EXPECT_CHAIN."
if [ "$CHAIN" = "137" ] && [ "${WLXON_I_ACCEPT_MAINNET_RISK:-}" != "1" ]; then
  die "chain 137 is Polygon MAINNET. Set WLXON_I_ACCEPT_MAINNET_RISK=1, or rehearse on a local 137 fork first."
fi
has_code "$(lc "$TARGET")" || die "no code at $TARGET on chain $CHAIN"

python3 "$PLAN_LIB" calltypes "$ARTIFACT" "$SIG" >/dev/null \
  || die "$SIG is not a function of the compiled $ARTIFACT artifact"
for a in $ADMIN_ARGS; do
  case "$a" in 0x*) addr_guard "$a" ARG ;; *[!0-9]*) die "ADMIN_ARGS token $a is neither an address nor a number" ;; esac
done

# ---- the custody question, asked of the chain ----------------------------------------------------
ADMIN_ID="$(rd "$TARGET" 'ADMIN_ROLE()(bytes32)')"
[ -n "$ADMIN_ID" ] || die "$TARGET does not expose ADMIN_ROLE() -- wrong artifact or wrong address"
holds="$(rd "$TARGET" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" "$(lc "$DEPLOYER")")"
[ "$holds" = "true" ] || die "$DEPLOYER does not hold ADMIN_ROLE on $TARGET (chain says $holds). This call would revert 'Only admin' and spend the nonce anyway."
DEFAULT_ID=0x0000000000000000000000000000000000000000000000000000000000000000
if [ "$DEPLOYER" = "$(lc "$DEPLOYER")" ]; then :; fi
say "custody: ADMIN_ROLE $ADMIN_ID on $TARGET is held by the SIGNER ($DEPLOYER) -- this call is NOT delayed."
say "        (wLXONSecure's admin is behind the 48 h timelock; this contract's constructor granted its"
say "        admin to msg.sender instead. Recorded in plan.json as custodyMode, not as a footnote.)"

# ---- nonce, fees -------------------------------------------------------------------------------
if [ -e "$PLAN_DIR" ] && [ -n "$(ls -A "$PLAN_DIR" 2>/dev/null || true)" ]; then
  die "$PLAN_DIR is not empty. A plan mixed with an earlier run's txs.jsonl is a batch whose nonces describe two ceremonies."
fi
mkdir -p "$PLAN_DIR"; CREATED_PLAN_DIR="$PLAN_DIR"; : > "$PLAN_DIR/txs.jsonl"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
p0="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
pp="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" pending --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$p0" ] || die "cannot read $DEPLOYER's nonce on chain $CHAIN"
[ "$p0" = "$pp" ] || die "$DEPLOYER has a transaction in flight (latest $p0, pending $pp); wait and re-plan."
START_NONCE="$(python3 -c "print(int('$p0',16))")"
PRIORITY="${MAX_PRIORITY_FEE:-}"
[ -n "$PRIORITY" ] || PRIORITY="$(cast rpc eth_maxPriorityFeePerGas --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$PRIORITY" ] || { sug="$(cast rpc eth_gasPrice --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"; PRIORITY="${sug:-0x1}"; }
PRIORITY="$(python3 -c "print(int('$PRIORITY',16))")"
BASE="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC_137" 2>/dev/null | python3 -c 'import sys,json;b=json.load(sys.stdin);b=b.get("result",b);print(int(b.get("baseFeePerGas","0x0"),16))' 2>/dev/null || echo '')"
if [ -n "${MAX_FEE:-}" ]; then MAXFEE="$MAX_FEE"; FEE_SOURCE="override"
else MAXFEE="$(python3 -c "print(2*(${BASE:-$PRIORITY} + $PRIORITY))")"; FEE_SOURCE="2x live base+tip"; fi
BAL="$(python3 -c "print(int('$(cast rpc eth_getBalance "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || echo 0x0)',16))")"

DATA="$(cast calldata "$SIG" $ADMIN_ARGS)"
if [ -n "$ADMIN_ARGS" ]; then
  back="$(cast calldata-decode "$SIG" "$DATA" 2>&1 | head -1 || true)"
  case "$back" in *Error*|*"could not"*) die "the calldata this script produced does not decode as $SIG: $back" ;; esac
else
  # A no-argument call has nothing to decode, so `cast calldata-decode` answers "no data was decoded" --
  # an error, but not this call's error. The round trip for a zero-argument signature is equality with
  # the selector alone: 4 bytes, nothing after it. Anything else means $SIG is not the call being made.
  SEL="$(cast sig "$SIG" 2>&1 | head -1)"
  printf '%s' "$SEL" | grep -Eq '^0x[0-9a-fA-F]{8}$' \
    || die "could not derive a 4-byte selector for $SIG (got: $SEL)"
  if [ "$(lc "$DATA")" != "$(lc "$SEL")" ] || [ "${#DATA}" -ne 10 ]; then
    die "$SIG is a no-argument call, so its calldata must be exactly the 4-byte selector $SEL -- this produced $DATA. Refusing to sign calldata with bytes after the selector for a signature that declares no arguments."
  fi
  say "calldata $DATA is the selector of $SIG exactly -- a zero-argument call, nothing to decode"
fi
json="{\"from\":\"$(lc "$DEPLOYER")\",\"to\":\"$(lc "$TARGET")\",\"data\":\"$DATA\"}"
est="$(cast rpc eth_estimateGas "$json" --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$est" ] || die "the node refused to estimate $SIG on $TARGET from $DEPLOYER -- it would revert on chain, so signing it only buys the gas it burns."
GAS="$(python3 -c "print(int('$est',16) * 115 // 100)")"

say "chain $CHAIN via $RPC_137 (phase $PHASE)"
say "target $TARGET   signer $DEPLOYER  nonce $START_NONCE (latest == pending)  balance $BAL wei POL"
say "gas    tip $PRIORITY wei ($(( PRIORITY / 1000000000 )) gwei), maxFee $MAXFEE wei ($FEE_SOURCE; base ${BASE:-n/a})"
python3 "$PLAN_LIB" add "call-$PHASE" "$START_NONCE" "$(lc "$TARGET")" 0 "$DATA" "$GAS" "$MAXFEE" "$PRIORITY" \
  "$CHAIN" "$DEPLOYER" "eth_estimateGas x1.15 (live code)" "$SIG args=[$ADMIN_ARGS] on $TARGET"
say "PLAN  call-$PHASE nonce=$START_NONCE -> $TARGET  gas=$GAS  data=${#DATA} hex"

PLAN_START_NONCE="$START_NONCE" PLAN_CHAIN_ID="$CHAIN" PLAN_DEPLOYER="$DEPLOYER" PLAN_RPC="$RPC_137" \
PLAN_MAX_FEE="$MAXFEE" PLAN_PRIORITY_FEE="$PRIORITY" PLAN_PHASE="direct-$PHASE" PLAN_STAMP="$STAMP" \
PLAN_ADMIN_TARGET="$TARGET" PLAN_ADMIN_SIG="$SIG" PLAN_ADMIN_ARGS="$ADMIN_ARGS" \
PLAN_FEE_SOURCE="$FEE_SOURCE" PLAN_CAPS_SOURCE="eth_estimateGas (live target)" PLAN_RESERVE=0 \
PLAN_TIMELOCK="$(rd "$TARGET" 'ADMIN_ROLE()(bytes32)')" \
  python3 "$PLAN_LIB" finish | python3 -c "import sys,json;d=json.load(sys.stdin);print('  plan.json: %s (%d tx, nonce %d, %d gas)' % (d['plan'],d['transactions'],d['startNonce'],d['totalGas']))"

# custodyMode: the deployer's own ADMIN_ROLE, verified above, with no delay in front of it.
python3 - "$PLAN_DIR/plan.json" "$DEPLOYER" "$TARGET" "$ADMIN_ID" <<'PY'
import json,sys
p,frm,target,role=sys.argv[1:5]
d=json.load(open(p))
d["custodyMode"]="direct-signer-admin"
d["custodyNote"]=("ADMIN_ROLE %s on %s is held by the signing key %s, which is why this plan has no %s "
  "waiting period and no proposal id. The migration contract's constructor granted roles to msg.sender; "
  "wLXONSecure's handed them to a TimelockController. Same deployer, two different custody rules -- read "
  "this field before describing the change as time-locked." % (role,target,frm,"48 h"))
json.dump(d,open(p,"w"),indent=1)
print("  custodyMode: %s" % d["custodyMode"])
PY

echo
echo "Next (same split as every other 137 ceremony):"
echo "  PLAN_DIR=$PLAN_DIR KEYSTORE=<the 137 keystore> PASSWORD_FILE=<pw file> bash script/polygon137/SignWlxon137Plan.sh"
echo "  PLAN_DIR=$PLAN_DIR SIGNED_DIR=$PLAN_DIR/signed bash script/polygon137/BroadcastWlxon137Signed.sh"
