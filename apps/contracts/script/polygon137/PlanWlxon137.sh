#!/usr/bin/env bash
# Plan the Polygon-137 wLXONSecure + migration ceremony as a batch of transactions, without a key.
#
#   PHASE=deploy  PLAN_DIR=/tmp/wlxon137-deploy DEPLOYER=0x… \
#   WLXON_NATIVE_LXON=0x… WLXON_TIMELOCK=0x… WLXON_MIGRATION_OLD=0x… \
#   WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
#
#   PHASE=fund    PLAN_DIR=/tmp/wlxon137-fund DEPLOYER=0x… \
#   WLXON_MIGRATION_NEW=0x… WLXON_MIGRATION=0x… WLXON_RESERVE=<wei> \
#   WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanWlxon137.sh
#
# Three scripts, because the key and the launch cannot be on the same machine and a plan is the only
# thing that can travel between them:
#
#   PlanWlxon137.sh          here. Needs an RPC and an address. Writes plan.json. No keystore, no signing.
#   SignWlxon137Plan.sh      on the key host. Needs the keystore and the plan. Signs, never broadcasts.
#   BroadcastWlxon137Signed.sh on the launch box. Needs the signatures and an RPC. Never sees a key.
#
# That split is not decoration. The address every later transaction names is decided by (sender, nonce)
# before anything is signed, so a plan can pin the whole ceremony -- deploy, wire, fund, open -- into
# nonces that have not happened yet. And a signature reveals nothing about the key that made it, so the
# directory that leaves the key host is safe to hand to anyone who is allowed to spend that gas.
#
# PHASE=deploy lands wLXONSecure and the migration contract, wired to each other, with the window closed.
# PHASE=fund pays the reserve and opens it. They are separate plans on purpose: the reserve is
# new-wLXON, which does not exist until the deploy phase has mined, so a single batch that deployed and
# funded would sign a transfer the signer cannot make. Fund before the window opens, not after: once
# startMigration lands, the holders who arrive first are the ones paid, and an under-funded contract
# fails on the ones who arrive later.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="script/polygon137/lib/offline_plan1559.py"
PLAN_LIB="script/polygon137/lib/plan137.py"

die() {
  echo "FATAL: $*" >&2
  # A plan dir this script created and then abandoned is a trap for the next run: the non-empty guard
  # is correct, but an operator who did not make the file cannot know which half is stale.
  [ -n "${CREATED_PLAN_DIR:-}" ] && [ "$CREATED_PLAN_DIR" = "${PLAN_DIR:-}" ] \
    && echo "       ($PLAN_DIR holds whatever this run wrote before it stopped -- start the next plan in a new directory)" >&2
  exit 1
}
CREATED_PLAN_DIR=""
say() { printf '  %s\n' "$*"; }
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

PHASE="${PHASE:-deploy}"
PLAN_DIR="${PLAN_DIR:?usage: PHASE=deploy|fund PLAN_DIR=<new dir> DEPLOYER=0x… bash script/polygon137/PlanWlxon137.sh}"
DEPLOYER="${DEPLOYER:?usage: DEPLOYER=<the 137 address that will sign this plan>}"
RPC_137="${RPC_137:-https://polygon-bor-rpc.publicnode.com}"
EXPECT_CHAIN="${WLXON_EXPECT_CHAIN_ID:-137}"

# A plan is the half that needs no secret. Refusing a key here is what keeps that true: the moment a
# planner can sign, "the machine that made the plan" and "the machine that holds the key" are one
# machine again, which is the arrangement this split exists to break.
[ -z "${PRIVATE_KEY:-}" ] || die "PLAN mode needs no key. PRIVATE_KEY= is refused here on purpose -- unset it."
[ -z "${KEYSTORE:-}" ] || die "PLAN mode needs no keystore; SignWlxon137Plan.sh is the script that uses one."
printf '%s' "$DEPLOYER" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "DEPLOYER=$DEPLOYER is not a 20-byte address"

addr_guard() { # addr name -- non-zero, well-formed, no placeholder left in the plan
  printf '%s' "$1" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "$2=$1 is not a 20-byte address"
  [ "$(lc "$1")" != "0x0000000000000000000000000000000000000000" ] || die "$2 is the zero address"
  case "$(lc "$1")" in
    0x00000000000000000000000000000000000000*|0x11111111111111111111111111111111111111*|0xdead0000000000000000000000000000000000*)
      die "$2=$1 looks like a placeholder. The checklist this ceremony replaces shipped 0x0 as a TODO; nothing is planned against a placeholder." ;;
  esac
}

# Wei amounts are compared in python, never with [ -lt ]: bash's integer tests are C longs, and a token
# or POL balance overflows one long before it is a large number -- 18.7 POL, the balance the real 137
# deployer holds, is 1.87e19 wei, past 2^63. `[ a -lt b ]` on those does not return a wrong answer, it
# refuses to answer, and a refusal read as "false" is a guard that silently lets everything through.
wei_lt() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1]) <  int(sys.argv[2]) else 1)" "$1" "$2"; }
wei_le() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1]) <= int(sys.argv[2]) else 1)" "$1" "$2"; }

case "$PHASE" in deploy|fund) ;; *) die "PHASE must be deploy or fund (got $PHASE)" ;; esac

# ---- the chain, before anything is measured against it ------------------------------------------
got_chain="$(cast rpc eth_chainId --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$got_chain" ] || die "$RPC_137 did not answer eth_chainId"
CHAIN="$(python3 -c "print(int('$got_chain',16))")"
[ "$CHAIN" = "$EXPECT_CHAIN" ] || die "$RPC_137 reports chain $CHAIN and this run is guarded for $EXPECT_CHAIN. A plan built on the wrong chain signs transactions that can never land there."
if [ "$CHAIN" = "137" ] && [ "${WLXON_I_ACCEPT_MAINNET_RISK:-}" != "1" ]; then
  die "chain 137 is Polygon MAINNET. Set WLXON_I_ACCEPT_MAINNET_RISK=1 to plan against it, or rehearse on Amoy (WLXON_EXPECT_CHAIN_ID=80002) or the local 137 fork first. Note that a chain-137 FORK answers 137 too -- this guard is about what the plan is for, and a fork rehearsal says so by setting the flag itself."
fi

if [ -e "$PLAN_DIR" ] && [ -n "$(ls -A "$PLAN_DIR" 2>/dev/null || true)" ]; then
  die "$PLAN_DIR is not empty. A plan mixed with an earlier run's txs.jsonl is a batch whose nonces describe two ceremonies."
fi
mkdir -p "$PLAN_DIR"
CREATED_PLAN_DIR="$PLAN_DIR"
: > "$PLAN_DIR/txs.jsonl"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- nonce: the fact that quietly ruins a launch -------------------------------------------------
p0="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
pp="$(cast rpc eth_getTransactionCount "$(lc "$DEPLOYER")" pending --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$p0" ] || die "cannot read $DEPLOYER's nonce on chain $CHAIN from $RPC_137 -- a plan built on a guessed nonce collides with whatever else this key sends"
[ "$p0" = "$pp" ] || die "$DEPLOYER has a transaction in flight (latest $p0, pending $pp). A plan signed now would reuse a nonce that is already moving; wait for it to mine and re-plan."
START_NONCE="$(python3 -c "print(int('$p0',16))")"

# ---- fees: EIP-1559 has two numbers and they are not interchangeable ----------------------------
PRIORITY="${MAX_PRIORITY_FEE:-}"
[ -n "$PRIORITY" ] || PRIORITY="$(cast rpc eth_maxPriorityFeePerGas --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
[ -n "$PRIORITY" ] || { sug="$(cast rpc eth_gasPrice --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"; PRIORITY="${sug:-0x1}"; }
PRIORITY="$(python3 -c "print(int('$PRIORITY',16))")"
BASE="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC_137" 2>/dev/null | python3 -c 'import sys,json;b=json.load(sys.stdin);b=b.get("result",b);print(int(b.get("baseFeePerGas","0x0"),16))' 2>/dev/null || echo '')"
if [ -n "${MAX_FEE:-}" ]; then
  MAXFEE="$MAX_FEE"
  if [ -n "$BASE" ] && [ "$MAXFEE" -lt "$(( BASE + PRIORITY ))" ]; then
    die "MAX_FEE=$MAXFEE is below base fee $BASE plus tip $PRIORITY. Every transaction would sit unswept once the base fee moved."
  fi
  FEE_SOURCE="override"
else
  MAXFEE="$(python3 -c "print(2*(${BASE:-$PRIORITY} + $PRIORITY))")"
  FEE_SOURCE="2x live base+tip"
fi
BAL="$(cast rpc eth_getBalance "$(lc "$DEPLOYER")" latest --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
BAL="$(python3 -c "print(int('${BAL:-0x0}',16))")"

say "chain $CHAIN via $RPC_137 (phase $PHASE)"
say "signer $DEPLOYER  nonce $START_NONCE (latest == pending)  balance $BAL wei POL"
say "gas    tip $PRIORITY wei ($(( PRIORITY / 1000000000 )) gwei), maxFee $MAXFEE wei ($FEE_SOURCE; base ${BASE:-n/a})"

# ---- the two helpers every step goes through ----------------------------------------------------
# `create` predicts the address the transaction will produce, refuses a prediction that already holds
# code, and prices the deploy with the node. `call` prices from the node when the target exists and
# from a measured cap when it does not -- a call aimed at a contract that is only created later in this
# same batch estimates at ~21000 whatever it actually costs, and out-of-gas mid-batch strands the rest.
NONCE="$START_NONCE"

estimate() { # estimate <to|"0x"> <data> -> gas number
  local to="$1" data="$2" json est
  if [ "$to" = "0x" ]; then json="{\"from\":\"$(lc "$DEPLOYER")\",\"data\":\"$data\"}"
  else json="{\"from\":\"$(lc "$DEPLOYER")\",\"to\":\"$to\",\"data\":\"$data\"}"; fi
  est="$(cast rpc eth_estimateGas "$json" --rpc-url "$RPC_137" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+' | head -1 || true)"
  [ -n "$est" ] || return 1
  python3 -c "print(int('$est',16) * 115 // 100)"
}

has_code() { # has_code <addr>
  local c; c="$(cast rpc eth_getCode "$1" latest --rpc-url "$RPC_137" 2>/dev/null | tr -d '"' || true)"
  [ -n "$c" ] && [ "$c" != "0x" ]
}

create() { # create <label> <artifact> <ctor args...>
  local label="$1" artifact="$2"; shift 2
  local sig data code args full g pred pc
  sig="$(python3 "$PLAN_LIB" ctorsig "$artifact")"
  code="$(python3 "$PLAN_LIB" bytecode "$artifact" 2>/dev/null)"
  args=""; [ $# = 0 ] || args="$(cast abi-encode "constructor($sig)" "$@")"
  full="${code}${args#0x}"
  pred="$(cast compute-address "$(lc "$DEPLOYER")" --nonce "$NONCE" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1 || true)"
  [ -n "$pred" ] || die "$label: cast compute-address gave no address for nonce $NONCE -- the prediction every later step names"
  pc="$(cast rpc eth_getCode "$(lc "$pred")" latest --rpc-url "$RPC_137" 2>/dev/null | tr -d '"' || true)"
  { [ -z "$pc" ] || [ "$pc" = "0x" ]; } || die "nonce $NONCE would deploy $label to $pred, which already has code. Either this plan was already broadcast or the nonce is not what the ceremony thinks it is -- read it before signing anything."
  g="$(estimate "0x" "$full")" || die "$label: the node refused to estimate this creation. The constructor would revert on chain, so signing it only buys the gas it burns."
  python3 "$PLAN_LIB" add "$label" "$NONCE" "0x" 0 "$full" "$g" "$MAXFEE" "$PRIORITY" "$CHAIN" "$DEPLOYER" "eth_estimateGas x1.15" "create $artifact args=[$*] -> $pred"
  say "PLAN  $label  nonce=$NONCE  create $artifact -> $pred  gas=$g  data=${#full} hex"
  # eval rather than a nameref: bash 3.2 -- the bash /bin/bash actually is on this machine -- has no
  # `declare -n`, and a plan whose predicted addresses came out empty would encode setNewToken(0x0).
  eval "PREDICTED_$label=\$pred"
  NONCE=$(( NONCE + 1 ))
}

call() { # call <label> <to> <sig> <capsig> <args...>
  local label="$1" to="$2" sig="$3" capkey="$4"; shift 4
  local data g source
  data="$(cast calldata "$sig" "$@")"
  # Round-trip the encoding through the decoder before it enters a plan. This is a formatting check,
  # not an authority check -- the authority is the on-chain readback, in the rehearsal and at launch.
  local back; back="$(cast calldata-decode "$sig" "$data" 2>&1 | head -1 || true)"
  case "$back" in *Error*|*"could not"*) die "$label: the calldata this script produced does not decode as $sig: $back" ;; esac
  if has_code "$(lc "$to")"; then
    g="$(estimate "$to" "$data")" || g=""
    source="eth_estimateGas x1.15"
    [ -n "$g" ] || { g="$(python3 "$PLAN_LIB" cap "$capkey")"; source="measured cap $capkey (target has code but this call reverts against current state)"; }
  else
    g="$(python3 "$PLAN_LIB" cap "$capkey")"
    source="measured cap $capkey (no code at $to yet; an estimate here would be 21000)"
  fi
  python3 "$PLAN_LIB" add "$label" "$NONCE" "$to" 0 "$data" "$g" "$MAXFEE" "$PRIORITY" "$CHAIN" "$DEPLOYER" "$source" "$sig args=[$*]"
  say "PLAN  $label  nonce=$NONCE  -> $to  $sig  args=[$*]  gas=$g  [$source]"
  NONCE=$(( NONCE + 1 ))
}

# ---- the ceremony itself ------------------------------------------------------------------------
WLXON_NAME="${WLXON_NAME:-Wrapped LXON}"
WLXON_SYMBOL="${WLXON_SYMBOL:-wLXON}"
WLXON_QUORUM="${WLXON_QUORUM:-2}"
[ "$WLXON_QUORUM" -ge 2 ] 2>/dev/null || die "WLXON_QUORUM=$WLXON_QUORUM: the constructor reverts below 2 (QuorumTooLow), because one signer is not a quorum -- it is one stolen key minting unlimited wLXON."

if [ "$PHASE" = "deploy" ]; then
  addr_guard "${WLXON_NATIVE_LXON:?WLXON_NATIVE_LXON=<the LXON token on the source side>}" WLXON_NATIVE_LXON
  addr_guard "${WLXON_MIGRATION_OLD:?WLXON_MIGRATION_OLD=<the legacy wLXON on chain 137>}" WLXON_MIGRATION_OLD
  WLXON_TIMELOCK="${WLXON_TIMELOCK:?WLXON_TIMELOCK=<a 137 timelock or multisig address, or 'create' to deploy one inside this batch>}"

  if [ "$(printf '%s' "$WLXON_TIMELOCK" | tr 'A-Z' 'a-z')" = "create" ]; then
    # The batch creates its own TimelockController and passes it the address it is *going* to have. That
    # is only safe because (sender, nonce) decides a CREATE address before anything is signed: the
    # timelock lands at nonce N, so its address is knowable while wLXONSecure at nonce N+1 is still being
    # encoded. minDelay is the entire point of this branch, so it is not allowed to be small.
    TIMELOCK_MODE="create"
    TL_MIN_DELAY="${TIMELOCK_MIN_DELAY:-172800}"
    printf '%s' "$TL_MIN_DELAY" | grep -Eq '^[0-9]+$' || die "TIMELOCK_MIN_DELAY=$TL_MIN_DELAY is not a number of seconds"
    [ "$TL_MIN_DELAY" -ge 172800 ] || die "TIMELOCK_MIN_DELAY=$TL_MIN_DELAY is under 48h (172800 s). A shorter delay is a countdown, not a guard against the deployer's own key."
    tl_array() { # "0x…,0x…" -> "[0x…,0x…]", each element verified and lowercased
      local out="[" a
      for a in ${1//,/ }; do
        printf '%s' "$a" | grep -Eq '^0x[0-9a-fA-F]{40}$' || die "$2 contains $a, which is not a 20-byte address"
        out="$out$(lc "$a"),"
      done
      printf '%s]' "$out"
    }
    ARR_PROPOSERS="$(tl_array "${TIMELOCK_PROPOSERS:-$DEPLOYER}" TIMELOCK_PROPOSERS)"
    ARR_EXECUTORS="$(tl_array "${TIMELOCK_EXECUTORS:-$DEPLOYER}" TIMELOCK_EXECUTORS)"
    TL_ADMIN="${TIMELOCK_ADMIN:-$DEPLOYER}"
    addr_guard "$TL_ADMIN" TIMELOCK_ADMIN
    say "custody: this batch CREATES a TimelockController -- minDelay $TL_MIN_DELAY s ($(( TL_MIN_DELAY / 3600 ))h)"
    say "         proposers $ARR_PROPOSERS  executors $ARR_EXECUTORS  DEFAULT_ADMIN $(lc "$TL_ADMIN")"
    create TIMELOCK TimelockController "$TL_MIN_DELAY" "$ARR_PROPOSERS" "$ARR_EXECUTORS" "$(lc "$TL_ADMIN")"
    TIMELOCK_ADDR="$PREDICTED_TIMELOCK"
  else
    TIMELOCK_MODE="existing"
    addr_guard "$WLXON_TIMELOCK" WLXON_TIMELOCK
    TL_MIN_DELAY=""
    # A timelock that is not a contract is not a timelock. The constructor accepts any non-zero address
    # for argument 6 and grants it ADMIN_ROLE, so an EOA -- or the Hardhat genesis account a local test
    # record left behind, or the LxonTokenEnhanced address that deployments/lxon-chain-724.json line 281
    # files under the name "timelock" -- passes every check that does not ask the chain whether the
    # address can execute anything. Then the bridge looks deployed and healthy forever while nothing can
    # ever queue behind a delay. Ask the chain.
    if ! has_code "$(lc "$WLXON_TIMELOCK")"; then
      echo "  NOTE: WLXON_TIMELOCK=$(lc "$WLXON_TIMELOCK") has no code on chain $CHAIN."
      echo "        ADMIN_ROLE would belong to an EOA or to an address that does not exist there, so there"
      echo "        is no delay mechanism on the other end of it: addAttestor, setQuorum, pauseBridge and"
      echo "        emergencyWithdraw all become one signature away, immediately."
      [ "${WLXON_I_ACCEPT_ADMIN_HAS_NO_CODE:-}" = "1" ] \
        || die "set WLXON_I_ACCEPT_ADMIN_HAS_NO_CODE=1 to plan a codeless admin deliberately, or point WLXON_TIMELOCK at a Timelock or multisig that exists on chain $CHAIN"
    fi
    if [ "$(lc "$WLXON_TIMELOCK")" = "$(lc "$DEPLOYER")" ]; then
      echo "  NOTE: WLXON_TIMELOCK == the deployer. Every admin gate on wLXONSecure -- addAttestor, setQuorum,"
      echo "        pauseBridge, emergencyWithdraw -- is then this one key, with no 48h delay in front of it."
      echo "        That is the DEFAULT_ADMIN-bypasses-the-timelock defect this deployment was meant to avoid."
      echo "        It is planned as asked and recorded in plan.json as a fact, not a detail."
      [ "${WLXON_I_ACCEPT_ADMIN_IS_DEPLOYER:-}" = "1" ] || die "set WLXON_I_ACCEPT_ADMIN_IS_DEPLOYER=1 to plan an un-timelocked wLXONSecure, or point WLXON_TIMELOCK at a real Timelock"
    fi
    TIMELOCK_ADDR="$(lc "$WLXON_TIMELOCK")"
  fi
  if [ "$WLXON_QUORUM" -gt "${WLXON_ATTESTOR_COUNT:-$WLXON_QUORUM}" ]; then
    die "WLXON_QUORUM=$WLXON_QUORUM above the attestor count ${WLXON_ATTESTOR_COUNT:-unknown}: setQuorum() above the registered set freezes the bridge with no way to mint. Register the attestors through the admin first."
  fi

  create WLXON wLXONSecure "$WLXON_NAME" "$WLXON_SYMBOL" "$(lc "$WLXON_NATIVE_LXON")" 724 "$CHAIN" "$TIMELOCK_ADDR" "$WLXON_QUORUM"
  create MIGRATION PolygonWLXONMigration

  call setOldToken "$PREDICTED_MIGRATION" "setOldToken(address)" setOldToken "$(lc "$WLXON_MIGRATION_OLD")"
  call setNewToken "$PREDICTED_MIGRATION" "setNewToken(address)" setNewToken "$(lc "$PREDICTED_WLXON")"

  # The attestor and relayer registrations belong to ADMIN_ROLE. When that is the timelock, the deployer
  # who signs this batch cannot make those calls at all, and planning them would sign transactions that
  # revert with MissingRole. They are printed instead, for whoever holds PROPOSER_ROLE.
  echo "  NOT PLANNED (ADMIN_ROLE is $TIMELOCK_ADDR, not the signer):"
  for a in ${WLXON_ATTESTORS//,/ }; do
    printf '    addAttestor(%s)  calldata %s\n' "$a" "$(cast calldata "addAttestor(address)" "$(lc "$a")")"
  done
  [ -n "${WLXON_RELAYER:-}" ] && printf '    addRelayer(%s)    calldata %s\n' "$(lc "$WLXON_RELAYER")" "$(cast calldata "addRelayer(address)" "$(lc "$WLXON_RELAYER")")"
  [ -n "${WLXON_ATTESTORS:-}${WLXON_RELAYER:-}" ] || echo "    (no WLXON_ATTESTORS / WLXON_RELAYER given: with zero attestors nothing can ever be minted or withdrawn)"
else
  addr_guard "${WLXON_MIGRATION_NEW:?WLXON_MIGRATION_NEW=<the wLXONSecure address from the deploy phase>}" WLXON_MIGRATION_NEW
  addr_guard "${WLXON_MIGRATION:?WLXON_MIGRATION=<the PolygonWLXONMigration address from the deploy phase>}" WLXON_MIGRATION
  RESERVE="${WLXON_RESERVE:?WLXON_RESERVE=<wei of new wLXON to park in the migration contract>}"
  printf '%s' "$RESERVE" | grep -Eq '^[0-9]+$' || die "WLXON_RESERVE=$RESERVE is not a wei integer"
  wei_lt 0 "$RESERVE" || die "WLXON_RESERVE is 0. A migration with no reserve cannot migrate anyone, and startMigration() would open a window in which every user reverts."
  DAYS="${WLXON_MIGRATION_DAYS:-30}"
  [ "$DAYS" -ge 7 ] || die "WLXON_MIGRATION_DAYS=$DAYS: the contract requires at least 7 days."
  # Checked with the other arguments, before the chain reads: a fund run that was not meant to open the
  # window should be told that immediately rather than after being shown a balance problem it did not ask
  # about, and an operator re-running it to fix the balance would still be signing the wrong intent.
  [ "${WLXON_START_MIGRATION:-}" = "1" ] || die "PHASE=fund exists to open the window; without WLXON_START_MIGRATION=1 it would only move tokens. Say you mean it, or park the reserve with a separate transfer."
  has_code "$(lc "$WLXON_MIGRATION_NEW")" || die "WLXON_MIGRATION_NEW=$WLXON_MIGRATION_NEW has no code on chain $CHAIN. The deploy phase must land first -- the reserve is paid in a token that does not exist yet."
  HELD="$(cast call "$(lc "$WLXON_MIGRATION_NEW")" "balanceOf(address)(uint256)" "$(lc "$DEPLOYER")" --rpc-url "$RPC_137" 2>/dev/null | awk '{print $1}')"
  [ -n "$HELD" ] || die "$RPC_137 did not answer balanceOf for $WLXON_MIGRATION_NEW"
  if wei_lt "$HELD" "$RESERVE"; then
    echo "FATAL: the reserve is not spendable yet. $DEPLOYER holds $HELD of new wLXON and this plan would move $RESERVE."
    echo "       That token only exists as an attested deposit (724 locks LXON, a quorum attests, the"
    echo "       destination mints) -- so bridge the reserve over first, or lower WLXON_RESERVE to what is"
    echo "       actually held. Planning the gap signs a batch that dies at its own first transfer." >&2
    exit 1
  fi

  call fundReserve "$(lc "$WLXON_MIGRATION_NEW")" "transfer(address,uint256)" fundReserve "$(lc "$WLXON_MIGRATION")" "$RESERVE"

  # ---- the legacy-retirement gate ----------------------------------------------------------------
  # Option one of the wLXON conversion decision (2026-10-27): the legacy Polygon token 0xB2CfeCb2… has
  # 4,010,000.000001 in supply, NONE of it backed (the "originalLXON" the 724 record names at 0x0a26E5CC…
  # has no code on chain 137), all of it sitting in one wallet -- 0x43410E73…, the developer key that is
  # reachable in git history -- and that same key can both burn and RE-MINT it (it holds MINTER_ROLE, whose
  # id is 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6, plus DEFAULT_ADMIN_ROLE).
  # Opening a 1:1 window against that supply turns unbacked paper into collateralised tokens, and turns a
  # leaked key into a claim on real LXON.
  #
  # The chain will NOT stop that. PolygonWLXONMigration's constructor granted its ADMIN_ROLE to msg.sender,
  # so startMigration() is one signature from this deployer with no timelock in front of it -- measured
  # 2026-10-27: hasRole(ADMIN_ROLE, deployer) = true, hasRole(ADMIN_ROLE, timelock) = false. That is the
  # asymmetry this gate exists to cover: wLXONSecure's admin is timelocked, the migration contract's is not.
  # So the question is asked of the chain here, and the answer must be "no supply left to redeem".
  LEGACY_ADDR="$(cast call "$(lc "$WLXON_MIGRATION")" 'oldWLXON()(address)' --rpc-url "$RPC_137" 2>/dev/null | awk '{print $1}')"
  [ -n "$LEGACY_ADDR" ] || die "$RPC_137 did not answer oldWLXON() on the migration contract -- the gate cannot be satisfied by a guess, because the address this check reads is the address the payout would redeem."
  LEGACY_SUPPLY="$(cast call "$(lc "$LEGACY_ADDR")" 'totalSupply()(uint256)' --rpc-url "$RPC_137" 2>/dev/null | awk '{print $1}')"
  [ -n "$LEGACY_SUPPLY" ] || die "$RPC_137 did not answer totalSupply() on the legacy token $LEGACY_ADDR"
  if wei_lt 0 "$LEGACY_SUPPLY"; then
    echo "  BLOCKED: the legacy token this window redeems still exists as supply."
    echo "    oldWLXON (read from the contract, not from your arguments) = $LEGACY_ADDR"
    echo "    its totalSupply                                            = $(python3 -c "print('%.6f' % (int('$LEGACY_SUPPLY')/10**18))") wLXON, of which"
    echo "    nothing is backed: the escrow on chain 724 that could pay for it measured 30,000 LXON (0.75%)."
    echo "    And 100% of it is held by a key that is in this repo's git history, which can also mint more."
    echo "    startMigration() is ADMIN_ROLE on the migration contract, and that role is THIS deployer --"
    echo "    one signature, no delay. So this refusal is a tooling gate, not a chain guarantee, and it is"
    echo "    the only thing between an unbacked 4.01M and a redeemable window."
    echo "    To open anyway: WLXON_I_ACCEPT_LEGACY_UNRETIRED=1. It is recorded in plan.json as a decision,"
    echo "    not a detail -- and the honest alternative is to leave the window closed and retire the legacy"
    echo "    supply first. See docs/runbooks/retire-legacy-wlxon-137.md."
    [ "${WLXON_I_ACCEPT_LEGACY_UNRETIRED:-}" = "1" ] \
      || die "refusing to plan a window over $LEGACY_SUPPLY wei of unbacked legacy wLXON"
    LEGACY_GATE="overridden"
  else
    LEGACY_GATE="passed"
    echo "  legacy supply retired: $LEGACY_ADDR reads totalSupply 0 -- a 1:1 window now redeems nothing that was never backed."
  fi
  if [ -n "${WLXON_LEGACY_TOP_HOLDER:-}" ]; then
    TOPH="$(cast call "$(lc "$LEGACY_ADDR")" "balanceOf(address)(uint256)" "$(lc "$WLXON_LEGACY_TOP_HOLDER")" --rpc-url "$RPC_137" 2>/dev/null | awk '{print $1}')"
    echo "  top holder $WLXON_LEGACY_TOP_HOLDER holds $(python3 -c "
s=int('${LEGACY_SUPPLY:-0}'); b=int('${TOPH:-0}')
print('%.1f%% of it' % (100.0*b/s) if s else '0 (supply is zero)')") of the legacy supply."
  fi

  call startMigration "$(lc "$WLXON_MIGRATION")" "startMigration(uint256)" startMigration "$(( DAYS * 86400 ))"
fi

# ---- cost it, then write it ----------------------------------------------------------------------
read -r TOTAL_GAS WORST_WEI <<EOF
$(python3 "$PLAN_LIB" reserve-gas)
EOF
# Compared in python (wei_le, defined above) rather than with [ -le ] -- see the note there.
wei_le "$WORST_WEI" "$BAL" || {
  echo "FATAL: the batch caps at $WORST_WEI wei POL of gas and $DEPLOYER holds $BAL."
  echo "       Nothing is signed yet, which is the point of costing a plan before it leaves." >&2
  exit 1
}

PLAN_DIR="$PLAN_DIR" PLAN_START_NONCE="$START_NONCE" PLAN_CHAIN_ID="$CHAIN" PLAN_DEPLOYER="$DEPLOYER" \
PLAN_RPC="$RPC_137" PLAN_MAX_FEE="$MAXFEE" PLAN_PRIORITY_FEE="$PRIORITY" PLAN_PHASE="$PHASE" \
PLAN_PREDICTED_WLXON="${PREDICTED_WLXON:-${WLXON_MIGRATION_NEW:-}}" \
PLAN_PREDICTED_TIMELOCK="${PREDICTED_TIMELOCK:-}" \
PLAN_PREDICTED_MIGRATION="${PREDICTED_MIGRATION:-${WLXON_MIGRATION:-}}" \
PLAN_LEGACY="${WLXON_MIGRATION_OLD:-}" PLAN_TIMELOCK="${TIMELOCK_ADDR:-${WLXON_TIMELOCK:-}}" \
PLAN_TIMELOCK_MODE="${TIMELOCK_MODE:-}" PLAN_TIMELOCK_MIN_DELAY="${TL_MIN_DELAY:-}" \
PLAN_QUORUM="$WLXON_QUORUM" \
PLAN_NATIVE_LXON="${WLXON_NATIVE_LXON:-}" PLAN_RESERVE="${RESERVE:-0}" \
PLAN_LEGACY_ADDR="${LEGACY_ADDR:-}" PLAN_LEGACY_SUPPLY="${LEGACY_SUPPLY:-}" PLAN_LEGACY_GATE="${LEGACY_GATE:-not-checked}" \
PLAN_MIGRATION_DAYS="${DAYS:-}" PLAN_OPENS_WINDOW="$([ "${WLXON_START_MIGRATION:-}" = "1" ] && echo 1 || echo 0)" \
PLAN_STAMP="$STAMP" PLAN_FEE_SOURCE="$FEE_SOURCE" \
python3 "$PLAN_LIB" finish >/dev/null || die "plan137.py finish refused this plan"

echo
echo "Plan written: $PLAN_DIR/plan.json (+ MANIFEST.txt, txs.jsonl)"
echo "  $(( NONCE - START_NONCE )) transactions, nonces $START_NONCE..$(( NONCE - 1 )),"
echo "  worst-case gas $WORST_WEI wei of the $BAL wei held."
echo "  Nothing was signed and nothing was broadcast -- this script cannot do either."
echo
echo "Next, on the machine that holds the keystore for $DEPLOYER:"
echo "  PLAN_DIR=$PLAN_DIR KEYSTORE=<keystore file or dir> PASSWORD_FILE=<file> bash script/polygon137/SignWlxon137Plan.sh"
echo "and back on this one, once the signed directory comes home:"
echo "  PLAN_DIR=$PLAN_DIR SIGNED_DIR=$PLAN_DIR/signed bash script/polygon137/BroadcastWlxon137Signed.sh"
