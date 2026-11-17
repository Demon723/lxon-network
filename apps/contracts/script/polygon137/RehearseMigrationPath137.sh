#!/usr/bin/env bash
# Drive the WHOLE migration path against the real, deployed Polygon-137 contracts on a fork -- the legacy
# wLXON exactly as it lives, the repointed destination token, and the migration contract -- before any
# holder is asked to surrender anything.
#
#   bash script/polygon137/RehearseMigrationPath137.sh
#
# Why this exists: `setNewToken(0x7A3c0C34…)` changed what migrating pays OUT of, and no test in this repo
# had ever exercised that pairing. The unit tests use a mock token; the migration contract's own hardening
# (check solvency BEFORE moving anything, no self-called migrateAll, recoverTokens cannot claw the reserve
# back) was proved against mocks. A mock cannot have the quirks of a contract for which no build exists in
# either repo -- the legacy token's 3,343 deployed bytes match nothing compiled here, so its behaviour is
# only knowable from the chain.
#
# Two things this needs that are not honest on mainnet, and are therefore done on a fork with the fork's
# own tools, stated where they happen:
#   * a user holding legacy wLXON is manufactured with anvil_setStorageAt at the balances slot -- and that
#     slot was not assumed, it was derived and then PROVEN by writing and reading balanceOf() back
#     (script/polygon137/lib/find_legacy_layout.py: totalSupply at slot 2, name/symbol at 3/4, so
#     OpenZeppelin 5.x's {0: _balances, 1: _allowances, 2: _totalSupply} and a write at keccak(addr,0)
#     landed exactly where balanceOf() reads it);
#   * the reserve is minted BY the bridge (0xbdc32d8c…) rather than by an attested claim, because the bridge
#     is the only minter -- which is also asserted, from a non-bridge caller.
# Nothing here moves real value: every state change is on a forked trie that dies with this script.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FORK_PORT="${FORK_PORT:-8552}"
F="http://127.0.0.1:$FORK_PORT"
UPSTREAM="${UPSTREAM:-https://polygon-bor-rpc.publicnode.com}"
LEG=0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6
DST=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
PM=0x642Af10C04a796aFc79BD3fC39c2336add2d957B
BRIDGE=0xbdc32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95
ADMIN=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
DEAD=0x000000000000000000000000000000000000dEaD   # surrendered tokens go here -- NOT address(0)
U=0xf00d000000000000000000000000000000000001
U2=0xf00d000000000000000000000000000000000002
E18=1000000000000000000
# wei <n> -> n * 10**18 as an exact decimal string. NEVER $(( n * E18 )): bash arithmetic is a 64-bit
# signed long, so 1000e18 silently wraps (measured: 1000*1e18 in $(( )) came out 3875820019684212736, which
# is 1e21 mod 2^64) and the fork would then be asserting against a number nobody chose.
wei(){ python3 -c "print(int($1) * 10**18)"; }

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$1"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
rpcv(){ cast rpc "$@" --rpc-url "$F" 2>&1 | tr -d '"'; }
# ask the node twice before believing it; a single connection reset from the fork's upstream looked exactly
# like "the token let a non-bridge account mint" -- which is a claim about security, and must not come from a
# network hiccup.
retry(){ local out i; for i in 1 2 3; do out="$("$@" 2>&1)"; case "$out" in
  *"connection reset"*|*"MPP HTTP request"*|*"timeout"*) sleep 2; continue ;; *) break ;; esac; done
  printf '%s' "$out"; }
rpcj(){ cast rpc "$@" --rpc-url "$F" 2>&1; }   # objects: do NOT strip quotes or it is not JSON
status_of(){ python3 -c "import sys,json;d=json.loads(sys.stdin.read());d=d.get('result',d);print(d.get('status','not mined') if isinstance(d,dict) else '?')" 2>/dev/null || echo parse-error; }
gasused_of(){ python3 -c "import sys,json;d=json.loads(sys.stdin.read());d=d.get('result',d);print(int(d['gasUsed'],16))" 2>/dev/null || echo 0; }
rd(){ cast call "$1" "$2" "${@:3}" --rpc-url "$F" 2>&1 | head -1 | awk '{print $1}'; }
w32(){ python3 -c "print('0x'+hex(int($1))[2:].rjust(64,'0'))"; }
# The legacy token's balances mapping sits at slot 0 -- derived from the chain and then PROVEN by writing:
# totalSupply at slot 2 with the name/symbol short-strings at 3/4 is OpenZeppelin 5.x's
# {0:_balances, 1:_allowances, 2:_totalSupply}, and lib/find_legacy_layout.py confirmed it by putting a value
# at keccak(addr,0) and reading it back out of balanceOf(). That proof is the only reason a storage write
# against a contract with no build in either repo is defensible at all -- a mapping slot guessed from
# convention is how a balance write lands inside somebody's allowance.
bal_slot(){ python3 -c "
import subprocess,sys
a=sys.argv[1].lower().replace('0x','').rjust(64,'0')
print(subprocess.run(['cast','keccak','0x'+a+'0'*64],capture_output=True,text=True).stdout.strip())" "$1"; }
send(){ # from to data -> tx hash, or the node's own error on stderr so an empty hash is never mistaken for a revert
  local out; out="$(rpcv eth_sendTransaction "{\"from\":\"$1\",\"to\":\"$2\",\"data\":\"$3\"}" 2>&1)"
  printf '%s' "$out" | grep -Eo '0x[0-9a-fA-F]{64}' | head -1
  if ! printf '%s' "$out" | grep -qE '0x[0-9a-fA-F]{64}'; then
    printf '     send from %s failed: %s\n' "$1" "$(printf '%s' "$out" | head -c 160)" >&2
  fi
}

WORK="$(mktemp -d /tmp/migpath-XXXXXX)"
ANVIL=""
trap '[ -n "$ANVIL" ] && kill "$ANVIL" 2>/dev/null; rm -rf "$WORK"' EXIT

BN="$(python3 -c "print(int('$(cast rpc eth_blockNumber --rpc-url "$UPSTREAM" | tr -d '"')',16))")"
anvil --fork-url "$UPSTREAM" --fork-block-number "$BN" --fork-chain-id 137 --port "$FORK_PORT" --auto-impersonate >"$WORK/anvil.log" 2>&1 &
ANVIL=$!
for _ in $(seq 1 60); do cast rpc eth_chainId --rpc-url "$F" >/dev/null 2>&1 && break; sleep 1; done

printf '\n== setup: a fork, the real contracts, and manufactured balances\n'
eq "0x89" "$(rpcv eth_chainId)" "forked chain 137"
eq "$DST" "$(rd $PM 'newWLXON()(address)')" "the fork inherited the repointed destination (0x7A3c0C34…)"
# The window's state is not something this script gets to assume. It used to assert
# `migrationActive == false` "as it is on mainnet", and mainnet changed on 2026-10-27 (deployer nonce 13
# ran startMigration), so the assertion failed and the two checks after it failed for a reason that had
# nothing to do with them: with the window open, `migrate()` gets past `whenMigrationActive` and dies on
# the manufactured holder's missing approval instead -- `0xfb8f41b2` = ERC20InsufficientAllowance, which
# is what this run reported as "migrate() ran with the window closed". So DRIVE the state instead of
# expecting it: fund and impersonate the admin (the fork's admin is the real 16.94 POL deployer key, and
# an unfunded impersonated sender answers -32003 -- the exact failure the bridge section above already
# documents), close the window if the fork inherited it open, and only then test closed-window behaviour.
ACTIVE0="$(rd $PM 'migrationActive()(bool)')"
printf '     inherited from mainnet: migrationActive=%s newWLXON=%s reserve=%s\n' "$ACTIVE0" \
  "$(rd $PM 'newWLXON()(address)')" "$(rd $PM 'reserveBalance()(uint256)' | awk '{print $1}')"
rpcv anvil_impersonateAccount "$ADMIN" >/dev/null
rpcv anvil_setBalance "$ADMIN" 0x152d02c7e14af6800000 >/dev/null
if [ "$ACTIVE0" = "true" ]; then
  send "$ADMIN" "$PM" "$(cast calldata 'endMigration()')" >/dev/null
  eq "false" "$(rd $PM 'migrationActive()(bool)')" "the fork inherited an OPEN window; endMigration() on the fork closed it, so the closed-window tests test a closed window"
else
  ok "the fork inherited a closed window; no state to drive"
fi
eq "0" "$(rd $PM 'reserveBalance()(uint256)')" "the reserve starts at zero, as it does on mainnet"
rpcv anvil_setBalance "$U" 0x152d02c7e14af6800000 >/dev/null    # 100 POL: 1 POL ran dry mid-script at this base fee
rpcv anvil_setBalance "$U2" 0x152d02c7e14af6800000 >/dev/null
SLOT_U="$(bal_slot "$U")"; SLOT_U2="$(bal_slot "$U2")"
rpcv anvil_setStorageAt "$LEG" "$SLOT_U" "$(w32 $(wei 1000))" >/dev/null
rpcv anvil_setStorageAt "$LEG" "$SLOT_U2" "$(w32 $(wei 50))" >/dev/null
eq "1000000000000000000000" "$(rd $LEG 'balanceOf(address)(uint256)' $U)" "the fork's legacy token reports the manufactured balance -- the balances slot is the one the layout proved, not the one convention suggested"
eq "50000000000000000000" "$(rd $LEG 'balanceOf(address)(uint256)' $U2)" "second holder funded too"

printf '\n== the reserve can only come from the bridge\n'
notm="$(retry rpcv eth_estimateGas "{\"from\":\"$ADMIN\",\"to\":\"$DST\",\"data\":\"$(cast calldata 'mint(address,uint256)' $PM "$(wei 600)")\"}")"
case "$notm" in
  *revert*) ok "a non-bridge mint reverts -- nobody with a key can conjure the reserve" ;;
  *"connection reset"*|*"MPP HTTP request"*) bad "the node never answered; this says nothing about the token, and is NOT counted as a pass" ;;
  *) bad "the destination token minted for a non-bridge caller ($notm)" ;;
esac
# The bridge has to be funded before it can mint, and that is the reason this rehearsal was failing rather
# than a property of the contract: anvil answers an unfunded impersonated sender with
# `-32003 Insufficient funds for gas * price + value`, and my send() helper greps a hash out of that and
# returns nothing, so every check downstream of the mint was reading an unchanged chain and calling it a
# failure. Naming the empty-hash case explicitly is what turned "the bridge cannot mint" into "the bridge had
# no POL" -- an assertion that can only say "no" cannot tell a bug from a defect.
rpcv anvil_impersonateAccount "$BRIDGE" >/dev/null
rpcv anvil_setBalance "$BRIDGE" 0x152d02c7e14af6800000 >/dev/null
printf '     the bridge holds %s wei on the fork (a contract, and a contract has no gas money of its own)\n' "$(rpcv eth_getBalance $BRIDGE latest)"
h="$(send "$BRIDGE" "$DST" "$(cast calldata 'mint(address,uint256)' $PM "$(wei 600)")")"
[ -n "$h" ] || bad "the bridge could not be made to mint even impersonated -- the mint path itself is unproven"
sleep 1
eq "600000000000000000000" "$(rd $PM 'reserveBalance()(uint256)')" "minted 600 by the bridge: reserveBalance is now 600 on the fork"

printf '\n== the window is closed until an admin opens it\n'
pre="$(rpcv eth_estimateGas "{\"from\":\"$U\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'migrate(uint256)' "$(wei 1)")\"}")"
case "$pre" in *"Migration not active"*) ok "migrate() while closed reverts 'Migration not active'" ;; *) bad "migrate() ran with the window closed: $pre" ;; esac
short="$(rpcv eth_estimateGas "{\"from\":\"$ADMIN\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'startMigration(uint256)' "$((6*86400))")\"}")"
case "$short" in *revert*) ok "startMigration refuses a duration under 7 days -- the door cannot be a revolving one" ;; *) bad "startMigration accepted 6 days: $short" ;; esac
h="$(send "$ADMIN" "$PM" "$(cast calldata 'startMigration(uint256)' "$((7*86400))")")"
r="$(rpcj eth_getTransactionReceipt "$h")"
gasmig="$(printf '%s' "$r" | gasused_of)"
eq "0x1" "$(printf '%s' "$r" | status_of)" "startMigration(7 days) mined"
eq "true" "$(rd $PM 'migrationActive()(bool)')" "window open"
nowts="$(cast rpc eth_getBlockByNumber latest false --rpc-url "$F" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16))')"
end="$(rd $PM 'migrationEndTime()(uint256)')"
python3 -c "import sys;sys.exit(0 if $end >= $nowts+7*86400-30 else 1)" \
  && ok "endTime ($end) is at least 7 days out from now ($nowts) -- startMigration(minDelay+now), not a bare now()" \
  || bad "endTime $end is not 7 days from $nowts"
printf '     measured gasUsed for startMigration on this pairing: %s gas\n' "$gasmig"

printf '\n== a holder migrates: 400 of their 1000\n'
h="$(send "$U" "$LEG" "$(cast calldata 'approve(address,uint256)' $PM "0x$(wei 1000)" | sed 's/^0x/0x/')")"
h2="$(send "$U" "$PM" "$(cast calldata 'migrate(uint256)' "$(wei 400)")")"
sleep 1
eq "600000000000000000000" "$(rd $LEG 'balanceOf(address)(uint256)' $U)" "user's legacy balance fell by 400"
eq "400000000000000000000" "$(rd $DST 'balanceOf(address)(uint256)' $U)" "user holds 400 of the destination token"
eq "200000000000000000000" "$(rd $PM 'reserveBalance()(uint256)')" "the reserve paid it out: 600 -> 200"
eq "400000000000000000000" "$(rd $LEG 'balanceOf(address)(uint256)' $DEAD)" "the surrendered 400 sits at 0xdead"
eq "4010000000001000000000000" "$(rd $LEG 'totalSupply()(uint256)')" "and the LEGACY totalSupply is UNCHANGED -- 0xdead is not a burn, exactly as the contract's comment says"
eq "400000000000000000000" "$(rd $PM 'totalMigrated()(uint256)')" "totalMigrated counts it"
eq "true" "$(rd $PM 'hasMigrated(address)(bool)' $U)" "the user is marked as having migrated"

printf '\n== the hardening: a migration this contract cannot pay for takes nothing\n'
over="$(rpcv eth_estimateGas "{\"from\":\"$U\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'migrate(uint256)' "$(wei 300)")\"}")"
case "$over" in *"Insufficient reserve"*|*InsufficientReserve*|*revert*) ok "asking for 300 against a 200 reserve is refused" ;; *) bad "over-reserve migrate did not revert: $over" ;; esac
# anvil will not mine a transaction whose estimate reverts -- eth_sendTransaction answers with the revert and
# no hash at all. So "mined with status 0x0" is not a thing a fork can show, and asserting it was measuring my
# harness. What is provable, and what actually matters, is that nothing moved.
# With gas money in the picture the fork DOES mine the transaction and let it fail, which is the stronger
# evidence anyway: it is not refused at the door, it executes and reverts, and the balances prove nothing
# moved. (Earlier this same line reported "accepted" because the test holder had run out of POL at a 250
# gwei base fee and the node answered -32003 -- an unfunded actor and a contract defect look identical
# through a helper that only greps for a hash.)
hf="$(send "$U" "$PM" "$(cast calldata 'migrate(uint256)' "$(wei 300)")")"
sleep 1
eq "0x0" "$(rpcj eth_getTransactionReceipt "$hf" | status_of)" "the unaffordable migration mined and FAILED -- it was not half-executed"
eq "600000000000000000000" "$(rd $LEG 'balanceOf(address)(uint256)' $U)" "the user still holds their 600 legacy tokens -- solvency is checked BEFORE any transfer"
eq "400000000000000000000" "$(rd $DST 'balanceOf(address)(uint256)' $U)" "and they received nothing"
eq "200000000000000000000" "$(rd $PM 'reserveBalance()(uint256)')" "and the reserve is untouched"

printf '\n== migrateAll, the call that used to revert on every single use\n'
# The holder has 600 legacy left and the reserve only 200 after the checks above, so migrateAll(600) is
# CORRECTLY refused -- an assertion about my sequencing, not the reentrancy fix. Top the reserve back up the
# way the real flow does (the bridge minting) so migrateAll is tested against a solvent contract.
rpcv anvil_setBalance "$BRIDGE" 0x152d02c7e14af6800000 >/dev/null
hb="$(send "$BRIDGE" "$DST" "$(cast calldata 'mint(address,uint256)' $PM "$(wei 400)")")"
sleep 1
eq "$(wei 600)" "$(rd $PM 'reserveBalance()(uint256)')" "reserve topped back to 600 by the bridge, matching the holder's remaining 600"
h="$(send "$U" "$PM" "$(cast calldata 'migrateAll()')")"
sleep 1
rr="$(rpcj eth_getTransactionReceipt "$h")"
st="$(printf '%s' "$rr" | status_of)"
eq "0x1" "$st" "migrateAll() mined (it used to self-call migrate() into ReentrancyGuardReentrantCall)"
eq "0" "$(rd $LEG 'balanceOf(address)(uint256)' $U)" "the holder is now out of legacy tokens"
eq "$(wei 1000)" "$(rd $DST 'balanceOf(address)(uint256)' $U)" "and holds 1000 destination tokens -- 400 migrated, then the remaining 600 via migrateAll: 1:1 with what they surrendered, no fee, no drift"
eq "0" "$(rd $PM 'reserveBalance()(uint256)')" "the reserve is drained dry (it had 600, migrateAll took 600)"
eq "$(wei 1000)" "$(rd $PM 'totalMigrated()(uint256)')" "totalMigrated now reads the whole 1000 this holder surrendered"
eq "$(wei 1000)" "$(rd $LEG 'balanceOf(address)(uint256)' $DEAD)" "and all 1000 of their legacy tokens are sitting at 0xdead"
empty="$(rpcv eth_estimateGas "{\"from\":\"$U\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'migrateAll()')\"}")"
case "$empty" in *revert*) ok "a second migrateAll() with no balance reverts rather than emitting a zero migration" ;; *) bad "empty migrateAll() did not revert: $empty" ;; esac
hd="$(send "$U2" "$PM" "$(cast calldata 'migrate(uint256)' "$(wei 10)")")"
sleep 1
eq "0x0" "$(rpcj eth_getTransactionReceipt "$hd" | status_of)" "and the NEXT holder hitting a drained reserve mines a FAILURE rather than taking tokens for nothing -- which is exactly why the window must not open before the money arrives"
eq "$(wei 50)" "$(rd $LEG 'balanceOf(address)(uint256)' $U2)" "and the refused holder still holds every one of their legacy tokens"

printf '\n== the reserve cannot be walked back out mid-migration\n'
rec="$(rpcv eth_estimateGas "{\"from\":\"$ADMIN\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'recoverTokens(address,uint256)' $DST "$(wei 50)")\"}")"
case "$rec" in *"Cannot recover reserve"*|*revert*) ok "recoverTokens(newWLXON) is refused while the window is open" ;; *) bad "the admin could withdraw the reserve mid-migration: $rec" ;; esac

printf '\n== closing the window\n'
h="$(send "$ADMIN" "$PM" "$(cast calldata 'endMigration()')")"
sleep 1
eq "false" "$(rd $PM 'migrationActive()(bool)')" "endMigration closes it"
after="$(rpcv eth_estimateGas "{\"from\":\"$U2\",\"to\":\"$PM\",\"data\":\"$(cast calldata 'migrate(uint256)' "$(wei 1)")\"}")"
case "$after" in *"Migration not active"*) ok "and a late holder is refused rather than left hanging mid-approve" ;; *) bad "migrate() still ran after endMigration: $after" ;; esac

printf '\n'
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1
