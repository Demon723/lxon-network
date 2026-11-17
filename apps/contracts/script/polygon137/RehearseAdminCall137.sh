#!/usr/bin/env bash
# Rehearse the DIRECT admin ceremonies on PolygonWLXONMigration against a chain-137 fork before anything
# is signed for mainnet: the one-argument repoint (setNewToken) and the zero-argument stop buttons
# (pauseMigration / unpauseMigration / endMigration / startMigration).
#
#   KEYSTORE=~/.lxon/keystores/polygon-137 PASSWORD_FILE=~/.lxon/secrets/polygon-137.pw \
#   bash script/polygon137/RehearseAdminCall137.sh
#
# What it is guarding, in one line: the migration contract's ADMIN_ROLE is the deployer key rather than a
# timelock, so none of these calls have 48 h in front of them -- which makes the pre-broadcast checks the
# only thing between a typo and a live change to what every legacy holder is paid in, or to whether they
# can claim at all. The window-state checks read the fork rather than a remembered answer, because the
# remembered answer (window closed, payout token = wLXONSecure) stopped being true on mainnet on
# 2026-10-27 and the rehearsal silently became a script that could only pass against history.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FORK_PORT="${FORK_PORT:-8550}"
FORK_RPC="http://127.0.0.1:$FORK_PORT"
UPSTREAM="${UPSTREAM:-https://polygon-bor-rpc.publicnode.com}"
D=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
PM=0x642Af10C04a796aFc79BD3fC39c2336add2d957B
PWX=0xD69fB341F35cadE285331797D7d35c5613D7Dfbe
NEW="${NEW_WLXON:-0x7A3c0C34f157EfDD3E4913c5224C15E645469093}"
KS="${KEYSTORE:?usage: KEYSTORE=… PASSWORD_FILE=… bash script/polygon137/RehearseAdminCall137.sh}"
PW="${PASSWORD_FILE:?usage: PASSWORD_FILE=<file holding the keystore password>}"
unset KEYSTORE PASSWORD_FILE

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$1"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
say(){ printf '  ·    %s\n' "$1"; }   # narration: measured facts, not a counted assertion
rpcv(){ cast rpc "$@" --rpc-url "$FORK_RPC" 2>&1 | tr -d '"'; }
rd(){ cast call "$1" "$2" "${@:3}" --rpc-url "$FORK_RPC" 2>/dev/null | head -1; }
rdq(){ rd "$@" | tr -d '"''"'; }
nonce_now(){ python3 -c "import sys;print(int(sys.argv[1],16))" "$(rpcv eth_getTransactionCount $DL latest | tr -d '\"')"; }

DL="$(printf %s "$D" | tr 'A-Z' 'a-z')"
NEWL="$(printf %s "$NEW" | tr 'A-Z' 'a-z')"
WORK="$(mktemp -d /tmp/adm137-rehearse-XXXXXX)"
ANVIL=""
trap '[ -n "$ANVIL" ] && kill "$ANVIL" 2>/dev/null; rm -rf "$WORK"' EXIT

BN="$(python3 -c "print(int('$(cast rpc eth_blockNumber --rpc-url "$UPSTREAM" | tr -d '"')',16))")"
anvil --fork-url "$UPSTREAM" --fork-block-number "$BN" --fork-chain-id 137 --port "$FORK_PORT" --auto-impersonate >"$WORK/anvil.log" 2>&1 &
ANVIL=$!
for _ in $(seq 1 60); do cast rpc eth_chainId --rpc-url "$FORK_RPC" >/dev/null 2>&1 && break; sleep 1; done

printf '\n== fork\n'
eq "137" "$(python3 -c "print(int('$(rpcv eth_chainId)',16))")" "the fork answers chain id 137"
rpcv anvil_setBalance "$DL" 0x152d02c7e14af6800000 >/dev/null
bal="$(python3 -c "print(int('$(rpcv eth_getBalance $DL latest)',16)//10**18)")"
[ "$bal" -ge 100 ] 2>/dev/null && ok "this is a fork, not Polygon ($D shows $bal POL; mainnet holds 16.987252)" \
  || { bad "the fork did not top up the deployer -- refusing to continue where a real broadcast would fit"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

printf '\n== the custody fact this script exists to check\n'
ADMIN_ID="$(rd "$PM" 'ADMIN_ROLE()(bytes32)')"
eq "true" "$(rd "$PM" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" "$DL")" "chain: the signer holds ADMIN_ROLE on the migration contract, so this call needs no timelock"
eq "false" "$(rd "$PM" "hasRole(bytes32,address)(bool)" "$ADMIN_ID" 0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054)" "chain: the 137 timelock does NOT admin the migration contract (so PlanAttestor137.sh is the wrong tool here, by design)"
# The before-state is MEASURED, not assumed. This script used to assert `newWLXON == wLXONSecure` and
# `migrationActive == false`, which were true the day it was written and false within hours of it -- the
# destination ruling (deployer nonce 12) and startMigration (nonce 13) both landed on mainnet -- so the
# rehearsal could no longer run at all. A rehearsal that only passes against one historical chain state
# is a rehearsal that trains its operator to ignore it, and this one is the only thing standing between
# a typo and a live change to what every legacy holder is paid in.
NEW_LIVE="$(rdq "$PM" 'newWLXON()(address)')"
ACTIVE_LIVE="$(rd "$PM" 'migrationActive()(bool)')"
RESERVE_LIVE="$(rd "$PM" 'reserveBalance()(uint256)' | awk '{print $1}')"
say "measured before-state: newWLXON=$NEW_LIVE migrationActive=$ACTIVE_LIVE reserve=$RESERVE_LIVE"
[ "$RESERVE_LIVE" = "0" ] || { bad "the reserve holds value on this fork -- refusing to rehearse admin calls that could change what users are paid in"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "before: the reserve is empty, so neither this repoint nor a window flip moves anyone's payout"
say "        (that refusal is the point: the moment a reserve exists, this rehearsal must be re-read, not re-run)"

printf '\n== the destination must be fit before anything points at it\n'
eq "18" "$(rd "$NEW" 'decimals()(uint8)' | awk '{print $1}')" "the new token has 18 decimals, the same unit legacy holders surrendered at"
eq "wLXON" "$(rdq "$NEW" 'symbol()(string)')" "the new token is the one named wLXON"
eq "0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95" "$(rd "$NEW" 'bridge()(address)')" "the new token's mint authority is the v4.1 bridge immutable, not any caller"
eq "0" "$(rd "$NEW" 'totalSupply()(uint256)' | awk '{print $1}')" "the new token has zero supply today, so nobody is being paid before collateral exists"

printf '\n== planner refusals\n'
t="$WORK/pk"; mkdir -p "$t"
out="$(env PRIVATE_KEY=0x$(printf '22%.0s' {1..64}) PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q PRIVATE_KEY && ok "refuses to plan with PRIVATE_KEY set" || bad "planned with a key in the environment"
t="$WORK/zero"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS=0x0000000000000000000000000000000000000000 RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses to repoint newWLXON at the zero address" || bad "planned newWLXON = 0x0"
t="$WORK/placeholder"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS=0x1111111111111111111111111111111111111111 RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses a placeholder address" || bad "planned against a placeholder"
t="$WORK/noadmin"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054 ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "does not hold ADMIN_ROLE" && ok "refuses a signer with no ADMIN_ROLE on the target (would revert 'Only admin')" || bad "planned a call the chain would refuse: $out"
t="$WORK/nosig"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" ADMIN_SIG='setNewToken(address,uint256)' RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refuses a signature the compiled artifact does not expose" || bad "planned a nonexistent signature"
t="$WORK/noack"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK= bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q MAINNET && ok "refuses a chain-137 plan without WLXON_I_ACCEPT_MAINNET_RISK=1" || bad "planned mainnet without the acknowledgement"

printf '\n== plan, sign, broadcast\n'
P1="$WORK/plan"; mkdir -p "$P1"
out="$(env PHASE=setNewToken PLAN_DIR="$P1" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)" \
  || { bad "the planner refused a call the chain accepts:"; printf '%s\n' "$out"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | sed 's/^/    /'
n0="$(python3 -c "import json;print(json.load(open('$P1/plan.json'))['startNonce'])")"
cm="$(python3 -c "import json;print(json.load(open('$P1/plan.json'))['custodyMode'])")"
eq "direct-signer-admin" "$cm" "the plan says out loud that this change was not time-locked"
eq "$n0" "$(nonce_now)" "the plan's nonce is the chain's nonce right now"
out="$(env PLAN_DIR="$P1" KEYSTORE="$KS" PASSWORD_FILE="$PW" bash script/polygon137/SignWlxon137Plan.sh 2>&1)" || { bad "the signer refused:"; printf '%s\n' "$out"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
cp -R "$P1/signed" "$WORK/tampered"; f="$(ls "$WORK"/tampered/00-*.raw.hex | head -1)"
python3 - "$f" <<'PY'
import sys
p=sys.argv[1]; b=bytearray.fromhex(open(p).read().strip()); b[-8]^=0x01; open(p,'w').write(b.hex())
PY
out="$(env PLAN_DIR="$P1" SIGNED_DIR="$WORK/tampered" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "a tampered signature is refused before publishing" || bad "the broadcaster accepted a tampered signature"
eq "$n0" "$(nonce_now)" "the tampered run moved no nonce"
out="$(env PLAN_DIR="$P1" SIGNED_DIR="$P1/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)" || { bad "the broadcast failed:"; printf '%s\n' "$out"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
printf '%s\n' "$out" | sed -n '/==>/,$p' | sed 's/^/    /'
eq "$NEW" "$(rd "$PM" 'newWLXON()(address)')" "chain after: newWLXON is the v4.1 bridge token"
eq "$ACTIVE_LIVE" "$(rd "$PM" 'migrationActive()(bool)')" "chain after: the window state is exactly as it was measured before (a repoint neither opens nor closes anything)"
eq "0" "$(rd "$PM" 'reserveBalance()(uint256)' | awk '{print $1}')" "chain after: the reserve is still 0 -- nothing became claimable"
eq "$NEW" "$(rd "$PM" 'newWLXON()(address)')" "and it survived the next call reading it back"
t="$WORK/replay"; mkdir -p "$t"
out="$(env PHASE=setNewToken PLAN_DIR="$t" DEPLOYER="$D" ADMIN_TARGET="$PM" ADMIN_ARGS="$NEW" RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 bash script/polygon137/PlanAdminCall137.sh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "re-planning the identical repoint is allowed (it is idempotent, so no paid revert is possible)" || bad "the planner refused a harmless idempotent re-run: $out"

printf '\n== the stop buttons: zero-argument admin calls, which this tool could not build until today\n'
# pauseMigration / unpauseMigration / endMigration take no arguments, and PolygonWLXONMigration has no
# PAUSER role -- every one of them is `onlyAdmin`, i.e. the same single deployer key as setNewToken. So
# the contract cannot be given "instant stop but no single-key admin" without redeploying it, and the
# obvious-sounding fix (hand ADMIN_ROLE to the 48 h timelock) would cost the only fast stop there is.
# That is why this section exists: the owner's documented options 1 and 2 are these two calls, and until
# now the planner could only ever encode `PHASE(address)`, so there was no rehearsed route to them.
HOLDER=0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27   # holds 100% of oldWLXON; used for revert probes only
paused_now(){ rd "$PM" 'paused()(bool)'; }
active_now(){ rd "$PM" 'migrationActive()(bool)'; }
migrate_probe(){ cast call "$PM" 'migrate(uint256)' 1000000000000000000 --from "$HOLDER" \
                   --rpc-url "$FORK_RPC" 2>&1 | head -1; }

plan_only(){ # plan_only <dir> <PHASE> <SIG> <ARGS> ; echoes the planner output, returns its code
  local d="$WORK/$1" ph="$2" sg="$3" ar="$4"; mkdir -p "$d"
  env PHASE="$ph" ADMIN_SIG="$sg" ADMIN_ARGS="$ar" PLAN_DIR="$d" DEPLOYER="$D" ADMIN_TARGET="$PM" \
      RPC_137="$FORK_RPC" WLXON_I_ACCEPT_MAINNET_RISK=1 \
      bash script/polygon137/PlanAdminCall137.sh 2>&1
}
ceremony(){ # ceremony <plan dir> -- sign with the real keystore, publish to the RPC the plan recorded (the fork)
  local d="$1" o
  o="$(env PLAN_DIR="$d" KEYSTORE="$KS" PASSWORD_FILE="$PW" bash script/polygon137/SignWlxon137Plan.sh 2>&1)" \
    || { bad "the signer refused $d: $(printf '%s' "$o" | tail -1)"; return 1; }
  o="$(env PLAN_DIR="$d" SIGNED_DIR="$d/signed" FORCE=1 bash script/polygon137/BroadcastWlxon137Signed.sh 2>&1)" \
    || { bad "the broadcast failed for $d: $(printf '%s' "$o" | tail -2)"; return 1; }
  return 0
}

out="$(plan_only pause pauseMigration 'pauseMigration()' '')"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "a zero-argument admin call plans (this is the shape the old planner refused)"
  # The planner skips its decode round trip for a no-argument call (there is nothing to decode), so the
  # calldata needs an anchor it did not produce itself: cast sig computes the selector from the signature
  # text, independently of the `cast calldata` encoder that wrote the plan.
  sel_p="$(cast sig 'pauseMigration()')"
  dat_p="$(python3 -c "import json;print(json.loads(open('$WORK/pause/txs.jsonl').readline())['data'])")"
  eq "$(printf '%s' "$sel_p" | tr 'A-Z' 'a-z')" "$(printf '%s' "$dat_p" | tr 'A-Z' 'a-z')" \
     "the planned calldata is exactly pauseMigration()'s selector as cast sig derives it, and nothing more"
  ceremony "$WORK/pause" && {
    eq "true" "$(paused_now)" "pauseMigration() landed: paused() is true on the fork"
    eq "$ACTIVE_LIVE" "$(active_now)" "pausing did not touch migrationActive -- pause and close are different buttons"
    out="$(migrate_probe)"
    printf '%s' "$out" | grep -qi "paus" && ok "a migrate() attempt while paused reverts on the pause ($out)" \
      || bad "a migrate() while paused did not revert on the pause: got [$out]"
  }
else
  bad "the planner still cannot build a no-argument call:"; printf '%s\n' "$out" | sed 's/^/    /'
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
out="$(plan_only unpa unpauseMigration 'unpauseMigration()' '')"; rc=$?
if [ "$rc" -eq 0 ]; then
  if ceremony "$WORK/unpa"; then
    eq "false" "$(paused_now)" "unpauseMigration() restores it, so the pause is reversible by the same key"
  fi
else
  bad "unpauseMigration refused to plan: $(printf '%s' "$out" | tail -1)"
fi

out="$(plan_only end endMigration 'endMigration()' '')"; rc=$?
[ "$rc" -eq 0 ] && ceremony "$WORK/end" && {
  eq "false" "$(active_now)" "endMigration() closed the window"
  out="$(migrate_probe)"
  printf '%s' "$out" | grep -q "Migration not active" && ok "and now every caller reverts 'Migration not active' ($out)" \
    || bad "migrate() did not revert with the contract's own reason: got [$out]"
} || { bad "endMigration refused to plan: $(printf '%s' "$out" | tail -1)"; }

out="$(plan_only end2 endMigration 'endMigration()' '')"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "estimate" \
  && ok "re-planning endMigration on a closed window is REFUSED before signing -- the estimateGas guard is what stops a paid revert on a call that is not idempotent" \
  || bad "the planner offered to sign a call the chain would revert: $(printf '%s' "$out" | tail -1)"

out="$(plan_only short startMigration 'startMigration(uint256)' 3600)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "estimate" \
  && ok "startMigration(3600) is refused pre-broadcast -- the contract's own 7-day floor, caught without spending a nonce" \
  || bad "the planner would have signed a below-floor window: $(printf '%s' "$out" | tail -1)"

out="$(plan_only reopen startMigration 'startMigration(uint256)' 2592000)"; rc=$?
[ "$rc" -eq 0 ] && ceremony "$WORK/reopen" && {
  eq "true" "$(active_now)" "startMigration(30 days) reopened it -- closing the window is NOT a one-way door"
  s="$(rd "$PM" 'migrationStartTime()(uint256)' | awk '{print $1}')"
  e="$(rd "$PM" 'migrationEndTime()(uint256)' | awk '{print $1}')"
  eq "2592000" "$(python3 -c "print($e-$s)")" "and the reopened window is the 30 days that was asked for"
} || { bad "the reopen rehearsal failed: $(printf '%s' "$out" | tail -1)"; }
eq "$NEW" "$(rd "$PM" 'newWLXON()(address)')" "the payout token survived all four window calls untouched"

printf '\n'
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1
