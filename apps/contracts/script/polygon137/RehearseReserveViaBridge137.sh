#!/usr/bin/env bash
# Rehearse the only way a migration reserve can ever exist: lock real LXON on 724, carry that crossing
# through the live v4.1 bridge, and have the mint land on the migration contract as the claim's recipient.
# Two anvil forks of the real chains, the real deployed bytecode on both sides, no production write.
#
#   bash script/polygon137/RehearseReserveViaBridge137.sh
#
# Why this exists. `reserveBalance()` is `newWLXON.balanceOf(address(this))`, and the new token's
# `mint(address,uint256)` reverts `not bridge` for every caller -- `bridge()` is an immutable, not an owner
# (measured on mainnet 2026-10-28). So the reserve cannot be topped up by a transfer, a donation, or a key;
# the only source is `claimTransfer` on the 137 bridge paying out in that token. Rehearsing the migration
# without rehearsing the crossing means rehearsing a number that is unreachable by construction.
#
# What it deliberately does NOT do: sign with the live attestor keys. All three v4.1 quorum wallets are
# plaintext `validator-{1,2,3}.hex` on this laptop, so they are available and using them here would still be
# wrong -- a signature over a real claim digest is valid on the real chain, and it does not stop being valid
# because it was submitted to a fork. Instead this script adds three THROWAWAY validators to the 137 fork by
# sending `addValidator` from the impersonated timelock, and signs with keys generated under a throwaway
# root that the trap destroys. The quorum arithmetic is then identical: `threshold()` stays 2 while the set
# grows, asserted from the chain rather than assumed.
#
# Two order-of-operations facts this run exists to pin down, because both are expensive to discover live:
#   * `lockTransfer` pulls with `safeTransferFrom`, so an `approve` on the 724 token must precede the lock;
#   * the first completed claim calls `_markUsed()`, which sets `configSealed` on 137 without revoking
#     DEFAULT_ADMIN -- so raising the inbound cap has to happen BEFORE the first claim, or it becomes a
#     48 h timelock batch.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC724_SRC="${RPC724_SRC:-https://rpc.lxon.in}"
RPC137_SRC="${RPC137_SRC:-https://polygon.drpc.org}"
P724="${P724_PORT:-18741}"; P137="${P137_PORT:-18742}"
F724="http://127.0.0.1:$P724"; F137="http://127.0.0.1:$P137"

B724=0x9B15fEe95995a15Da2d64D8E2958f9792D5D6a25      # v4.1 bridge on 724 (sealed, 3 validators)
B137=0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95      # v4.1 bridge on 137 (unsealed, never used)
TL137=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5     # 137 bridge timelock, minDelay 172800
WLXON=0x7A3c0C34f157EfDD3E4913c5224C15E645469093     # new wLXON: the inbound payout token
LEG=0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6       # legacy wLXON, supply 4,010,000.000001
PM=0x642Af10C04a796aFc79BD3fC39c2336add2d957B        # PolygonWLXONMigration -- the claim's recipient
LXON724=0x99801a78639975d448eeb2f8a807738dc8df67dc   # the token locked on 724
HOLDER=0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27    # holds 100% of legacy
LOCKER=0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA    # holds 89,908,900 LXON on 724
ADMIN137=0x2a8Ca01C53cecF360b181a0B7D49a71565684665  # 137 deployer: DEFAULT_ADMIN on both contracts
DEAD=0x000000000000000000000000000000000000dEaD
TRANCHE=100000                                        # the owner's chosen size -- equals the live cap
E18=1000000000000000000

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$*"; }
bad(){ FAIL=$((FAIL+1)); printf '  BAD  %s\n' "$*"; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want [$1] got [$2])"; fi; }
say(){ printf '  ·    %s\n' "$1"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# Every wei product goes through python. `bash` arithmetic is 64-bit: 100000 * 10**18 wraps, and a `test`
# on the wrapped value errors rather than answering, which a caller reads as false.
w(){ python3 -c "print($1)"; }
j(){ curl -s --max-time 90 -X POST -H 'Content-Type: application/json' -d "$2" "$1"; }
# params is passed as a complete JSON ARRAY by every caller. Wrapping it here too (`"params":[$3]`) sends
# anvil `[["0x…","0x…"]]`, which fails as `invalid type: string, expected u8` -- and because the failure is
# an error object rather than a missing key, the funding call silently did nothing and every receipt read
# came back `parse-error` while the transactions themselves had mined. Read the error object, not just it.
rpc(){ j "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}"; }
field(){ # prints the field, or the RPC error verbatim -- a missing value and a rejected request are not the
  # same event, and reporting both as "parse-error" is how a broken helper hides for three runs.
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("unreadable-reply"); raise SystemExit
if "error" in d:
    print("rpc-error:" + str(d["error"].get("message", ""))[:70]); raise SystemExit
r = d.get("result")
print("" if r is None else (r.get(sys.argv[1], "absent-field") if isinstance(r, dict) else r))' "$1"; }
rd(){ cast call "$1" "$2" "${@:3}" --rpc-url "$F137" 2>/dev/null | head -1; }
rd724(){ cast call "$1" "$2" "${@:3}" --rpc-url "$F724" 2>/dev/null | head -1; }
fund(){ # anvil_setBalance, hex derived in python: bash's printf %x wraps above 2**63-1, and an amount
  # like 100 POL silently becomes a small negative-looking value, so the fork would not be funded.
  # Written with argv, not nested quotes: bash 3.2 cannot nest "…" inside $( … ) inside "…", and the
  # failure it produces is a parse error on the LAST line of the file, nowhere near the cause.
  local u="$1" a="$2" hexv
  hexv="$(python3 -c 'import sys;print(hex(int(sys.argv[1])))' "$3")"
  rpc "$u" anvil_setBalance "[\"$a\",\"$hexv\"]" >/dev/null
}
send(){ # send <rpc> <from> <to> <sig> [args...] -> tx hash, or empty on failure
  # Measured on foundry 1.8.6: `cast send --json` returns {"schema_version","success","data","errors"}
  # with data:null EVEN ON A SUCCESSFUL SEND, so parsing the hash out of it yields "" and every receipt
  # read downstream reports "parse-error" for a transaction that mined. The text form prints the receipt
  # field by field, so read it BY NAME -- `blockHash` and the padded log addresses are also 0x+64hex, and
  # "the last hex string in the output" is how a ceremony records a block hash as a transaction hash.
  # The raw output is kept per send so a failure is diagnosable instead of silent.
  local u="$1" f="$2" t="$3" d="$4"; shift 4
  # tee, not `> file | awk`: redirecting stdout to the log and piping to awk at the same time gives awk
  # an empty stream, so every hash reads back blank and each send looks like it never mined -- which is
  # exactly the wrong answer, because the transaction did land.
  cast send --rpc-url "$u" --unlocked --from "$f" "$t" "$d" "$@" 2>&1 \
    | tee "$ROOT/last-send.log" | awk '$1=="transactionHash"{print $2}' | head -1
}
failmsg(){ printf '%s' "$(tail -2 "$ROOT/last-send.log" | tr '\n' ' ')" | cut -c1-140; }

ROOT="$(mktemp -d /tmp/reserve-rehearse-XXXXXX)"; KEYS="$ROOT/keys"; mkdir -p "$KEYS"
PWP="$ROOT/keys.pw"; printf 'rehearsal-throwaway-only\n' > "$PWP"; chmod 600 "$PWP"
A724=""; A137=""
cleanup(){ [ -n "$A724" ] && kill "$A724" 2>/dev/null; [ -n "$A137" ] && kill "$A137" 2>/dev/null
           rm -rf "$ROOT"; }
trap cleanup EXIT

printf '\n== two forks, and the lane exactly as the chains have it\n'
anvil --fork-url "$RPC724_SRC" --chain-id 724 --port "$P724" --auto-impersonate >"$ROOT/anvil724.log" 2>&1 & A724=$!
anvil --fork-url "$RPC137_SRC" --chain-id 137 --port "$P137" --auto-impersonate >"$ROOT/anvil137.log" 2>&1 & A137=$!
for _ in $(seq 1 90); do
  cast rpc eth_chainId --rpc-url "$F724" >/dev/null 2>&1 && cast rpc eth_chainId --rpc-url "$F137" >/dev/null 2>&1 && break
  sleep 2; done
eq "724" "$(cast chain-id --rpc-url "$F724")" "the 724 fork answers chain id 724"
eq "137" "$(cast chain-id --rpc-url "$F137")" "the 137 fork answers chain id 137"
eq "$B137" "$(rd724 "$B724" 'peerBridges(uint256)(address)' 137)" "724 fork: the 137 peer is the bridge that will pay out"
eq "$B724" "$(rd "$B137" 'peerBridges(uint256)(address)' 724)"   "137 fork: the 724 peer is the bridge that will lock"
eq "$WLXON" "$(rd "$PM" 'newWLXON()(address)')" "137 fork: the migration pays out in the bridge's wLXON"
INB="$(cast call "$B137" 'inbound(uint256,address)(address,uint8,uint256,bool)' 724 "$LXON724" --rpc-url "$F137" | tr '\n' ' ')"
AMT="$(w "$TRANCHE * $E18")"
say "inbound(724, LXON724) = $INB"
eq "$AMT" "$(printf '%s' "$INB" | awk '{print $3}')" "the cap is exactly $TRANCHE -- the owner's tranche fits, and a bigger one needs a raise FIRST"
eq "true" "$(printf '%s' "$INB" | awk '{print $5}')" "the lane is live (fields are address, payout, cap, the [1e23] hint, live -- do not read the hint as a value)"
eq "false" "$(rd "$B137" 'everUsed()(bool)')" "137 has never settled a claim -- this is the first one"
eq "false" "$(rd "$B137" 'configSealed()(bool)')" "137 is still configurable today"
eq "true"  "$(rd "$PM" 'migrationActive()(bool)')" "and the window is OPEN on mainnet (startMigration ran; endMigration was planned but never broadcast)"
eq "0" "$(rd "$PM" 'reserveBalance()(uint256)' | awk '{print $1}')" "with an empty reserve, which is what the crossing below fixes"

printf '\n== attestors: the live set is SWAPPED for throwaways on the fork, never extended\n'
# Found by running this: quorumFloor() is `admissibleCount() / 2 + 1`, so ADDING three throwaway validators
# to the three live ones took the floor from 2 to 4 and the two-signature bundle reverted
# `below quorum floor`. Two of three is a quorum only while the set is three. So the rehearsal removes the
# live validators after adding the throwaways -- add first, because removeValidator insists at least
# `threshold` signers remain. The same arithmetic governs a real rotation: a batch that adds without
# removing in the same transaction raises how many signatures every later claim needs.
VS=""
for n in 1 2 3; do
  CAST_PASSWORD='rehearsal-throwaway-only' cast wallet new "$KEYS" "throwaway-$n" >/dev/null 2>&1 \
    || bad "could not generate throwaway attestor key $n"
  a="$(cast wallet address --keystore "$KEYS/throwaway-$n" --password-file "$PWP" 2>/dev/null | grep -Eo '0x[0-9a-fA-F]{40}' | head -1)"
  [ -n "$a" ] || { bad "no address came out of throwaway-$n"; continue; }
  VS="$VS $a"
done
set -- $VS
V1="$1"; V2="$2"; V3="$3"
[ -n "$V1" ] && [ -n "$V2" ] && [ -n "$V3" ] && ok "three throwaway attestor wallets: $V1 $V2 $V3 (addresses only; keystores die with $ROOT)"
N0="$(rd "$B137" 'validatorCount()(uint256)' | awk '{print $1}')"
FLOOR0="$(rd "$B137" 'quorumFloor()(uint256)' | awk '{print $1}')"
eq "3" "$N0" "the live 137 set is 3 validators before this rehearsal touches it"
eq "2" "$FLOOR0" "and quorumFloor is 2 -- floor = admissibleCount/2 + 1, read from the chain"
REAL0="$(rd "$B137" 'validatorAt(uint256)(address)' 0)"; REAL1="$(rd "$B137" 'validatorAt(uint256)(address)' 1)"
REAL2="$(rd "$B137" 'validatorAt(uint256)(address)' 2)"
say "the three live wallets being stepped aside on this fork only: $REAL0 $REAL1 $REAL2"
fund "$F137" "$TL137" 100000000000000000000
TLBAL="$(rpc "$F137" eth_getBalance "[\"$TL137\",\"latest\"]" | field result)"
if [ "$TLBAL" = "0x0" ] || [ -z "$TLBAL" ]; then
  bad "the timelock is still unfunded on the fork ($TLBAL) -- every addValidator would fail as 'Out of gas', so this is the funding helper, not the bridge"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "the impersonated timelock holds gas on the fork -- funding works, which is what the adds below depend on"
ADDED=0
for v in "$V1" "$V2" "$V3"; do
  hh="$(send "$F137" "$TL137" "$B137" 'addValidator(address)' "$v")"
  if [ -n "$hh" ]; then ADDED=$((ADDED + 1)); else say "addValidator($v) returned no hash: $(failmsg)"; fi
done
say "addValidator hashes captured: $ADDED of 3 -- the count below is the authority, not this number"
for v in "$REAL0" "$REAL1" "$REAL2"; do
  hh="$(send "$F137" "$TL137" "$B137" 'removeValidator(address)' "$v")"
  [ -n "$hh" ] || say "removeValidator($v) returned no hash: $(failmsg)"
done
eq "3" "$(rd "$B137" 'validatorCount()(uint256)' | awk '{print $1}')" "the set is back to 3 after three adds and three removals -- chain state is the authority here, because anvil can answer a mining send with a fork-fetch error (publicnode 403s on archive reads) and still have landed the transaction"
eq "2" "$(rd "$B137" 'quorumFloor()(uint256)' | awk '{print $1}')" "the floor is back to 2, which is what makes a two-signature bundle legal again"
eq "2" "$(rd "$B137" 'threshold()(uint256)' | awk '{print $1}')" "threshold stayed 2 -- two signatures are a quorum here, exactly as two real ones would be"
eq "true" "$(rd "$B137" 'isValidValidator(address)(bool)' "$V1")" "throwaway 1 is admissible"
eq "true" "$(rd "$B137" 'isValidValidator(address)(bool)' "$V2")" "throwaway 2 is admissible"
eq "false" "$(rd "$B137" 'isValidValidator(address)(bool)' "$REAL0")" "and a live wallet is no longer admissible on this fork -- the swap went the right way"

printf '\n== step 1: approve, then lock %s LXON on 724 with the migration contract as recipient\n' "$TRANCHE"
AMT="$(w "$TRANCHE * $E18")"
fund "$F724" "$LOCKER" 100000000000000000000
BEFORE="$(rd724 "$LXON724" 'balanceOf(address)(uint256)' "$LOCKER" | awk '{print $1}')"
ESC0="$(rd724 "$B724" 'escrowed(address)(uint256)' "$LXON724" | awk '{print $1}')"
h_ap="$(send "$F724" "$LOCKER" "$LXON724" 'approve(address,uint256)' "$B724" "$AMT")"
eq "0x1" "$([ -n "$h_ap" ] && rpc "$F724" eth_getTransactionReceipt "[\"$h_ap\"]" | field status || echo "no-hash:$h_ap")" "approve() mined -- lockTransfer pulls with safeTransferFrom, so without it the lock reverts"
eq "$AMT" "$(rd724 "$LXON724" 'allowance(address,address)(uint256)' "$LOCKER" "$B724" | awk '{print $1}')" "the 724 bridge is allowed exactly the tranche"
h_lock="$(send "$F724" "$LOCKER" "$B724" 'lockTransfer(address,uint256,uint256,address)' "$LXON724" "$AMT" 137 "$PM")"
st_lock="$(rpc "$F724" eth_getTransactionReceipt "[\"$h_lock\"]" | field status)"
eq "0x1" "$st_lock" "lockTransfer mined with recipient = the migration contract"
GAS_LOCK="$(rpc "$F724" eth_getTransactionReceipt "[\"$h_lock\"]" | field gasUsed)"
say "gasUsed: approve + lockTransfer on 724 (raw hex from the receipt): $GAS_LOCK"
eq "$(w "$BEFORE - $AMT")" "$(rd724 "$LXON724" 'balanceOf(address)(uint256)' "$LOCKER" | awk '{print $1}')" "the locker paid the tranche"
eq "$(w "$ESC0 + $AMT")" "$(rd724 "$B724" 'escrowed(address)(uint256)' "$LXON724" | awk '{print $1}')" "the bridge's own escrow ledger for LXON724 rose by exactly the tranche -- that ledger, not a balance, is what a release is measured against"

printf '\n== step 2: rebuild the claim from the event; let the contract witness its own digest\n'
LB="$(rpc "$F724" eth_getTransactionReceipt "[\"$h_lock\"]" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["blockNumber"])')"
# ^ straight from the JSON-RPC receipt, so it is a hex quantity. `cast receipt <h> blockNumber` prints a
# *decimal* block number, and feeding that to eth_getBlockByNumber asks the node for a different block.
LOGJSON="$(cast logs --rpc-url "$F724" --address "$B724" --from-block "$LB" --to-block "$LB" --json 2>/dev/null)"
CLAIM_ID="$(printf '%s' "$LOGJSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["topics"][1])')"
DATA="$(printf '%s' "$LOGJSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["data"])')"
BLOCKHASH="$(printf '%s' "$(rpc "$F724" eth_getBlockByNumber "[\"$LB\",false]")" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["hash"])')"
python3 - "$DATA" > "$ROOT/fields.sh" <<'PY'
import sys
d = sys.argv[1].removeprefix('0x')
wd = [d[i:i+64] for i in range(0, len(d), 64)]
assert len(wd) == 12, "expected 12 words in TransferLocked data, got %d" % len(wd)
# Request is (uint256,address,address,uint256,uint256,uint256,address,uint256,address,address,uint256)
kind = ['u','a','a','u','u','u','a','u','a','a','u']
names = ("SRC_CHAIN","SRC_BRIDGE","DEST_BRIDGE","DEST_CHAIN","LANE_NONCE","SRC_TOTAL","SRC_TOKEN","CLAIM_AMT","SENDER","RECIPIENT","SRC_BLOCK")
parts = []
for k, x in zip(kind, wd[:11]):
    parts.append("0x" + x[-40:] if k == 'a' else str(int(x, 16)))
print('REQ_TUPLE="(%s)"' % ",".join(parts))
for nm, k, x in zip(names, kind, wd[:11]):
    print('%s=%s' % (nm, ("0x"+x[-40:]) if k == 'a' else int(x, 16)))
print('CREDITED=%d' % int(wd[11], 16))
PY
. "$ROOT/fields.sh"
eq "$(lc "$PM")" "$(lc "$RECIPIENT")" "the decoded claim pays the migration contract"
eq "$AMT" "$CLAIM_AMT" "the amount in the emitted claim is exactly the amount this script asked the bridge to lock (the decoded field is CLAIM_AMT -- naming it AMT would have clobbered the shell's own value and made this check a tautology)"
eq "$TRANCHE" "$(w "$CLAIM_AMT // $E18")" "the claim's amount is the tranche, and the credited amount is $(w "$CREDITED // $E18") -- an untaxed token, so escrow equals request (integer division: a float prints 100000.0 and fails the compare)"
eq "1" "$LANE_NONCE" "laneNonce 1 -- no crossing has ever used this lane"
LOCAL_ID="$(cast keccak "$(cast abi-encode 'f((uint256,address,address,uint256,uint256,uint256,address,uint256,address,address,uint256))' "$REQ_TUPLE")")"
eq "$CLAIM_ID" "$LOCAL_ID" "claimId recomputed locally equals the topic the bridge emitted"
DIG="$(rd "$B137" 'claimDigest(bytes32,bytes32)(bytes32)' "$CLAIM_ID" "$BLOCKHASH")"
say "claimDigest() from the destination contract: $DIG"
[ -n "$DIG" ] && [ "${#DIG}" -eq 66 ] && ok "the contract produced a 32-byte digest for this claim+block" || bad "claimDigest did not return a 32-byte value"

printf '\n== step 3: two throwaway signatures, ordered by recovered signer, claimed on 137\n'
S1="$(cast wallet sign --no-hash --keystore "$KEYS/throwaway-1" --password-file "$PWP" "$DIG")"
S2="$(cast wallet sign --no-hash --keystore "$KEYS/throwaway-2" --password-file "$PWP" "$DIG")"
R1A="$(cast call "$B137" 'attestorOf(bytes32,bytes32,bytes)(address,bool)' "$CLAIM_ID" "$BLOCKHASH" "$S1" --rpc-url "$F137" 2>/dev/null)"
REC1="$(printf '%s' "$R1A" | sed -n 1p)"; ADM1="$(printf '%s' "$R1A" | sed -n 2p)"
eq "$(lc "$V1")" "$(lc "$REC1")" "the contract recovers throwaway 1 from that signature"
eq "true" "$ADM1" "and admits it"
if [ "$(lc "$V1")" \< "$(lc "$V2")" ]; then BUNDLE="[$S1,$S2]"; else BUNDLE="[$S2,$S1]"; fi
fund "$F137" "$ADMIN137" 100000000000000000000
[ -n "${h_cl:-}" ] || true
h_cl="$(send "$F137" "$ADMIN137" "$B137" 'claimTransfer((uint256,address,address,uint256,uint256,uint256,address,uint256,address,address,uint256),bytes32,bytes[])' "$REQ_TUPLE" "$BLOCKHASH" "$BUNDLE")"
[ -n "$h_cl" ] || say "claimTransfer produced no hash: $(failmsg)"
eq "0x1" "$([ -n "$h_cl" ] && rpc "$F137" eth_getTransactionReceipt "[\"$h_cl\"]" | field status || echo no-hash)" "claimTransfer mined"
say "gasUsed: claimTransfer on 137 = $(rpc "$F137" eth_getTransactionReceipt "[\"$h_cl\"]" | field gasUsed)"
eq "$AMT" "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$PM" | awk '{print $1}')" "the migration contract holds the tranche in new wLXON"
eq "$AMT" "$(rd "$PM" 'reserveBalance()(uint256)' | awk '{print $1}')" "reserveBalance() now reads it -- created by a real crossing, not by a config call"
eq "$AMT" "$(rd "$WLXON" 'totalSupply()(uint256)' | awk '{print $1}')" "the new token's whole supply is backed by the 724 escrow measured above: 1:1"
eq "true" "$(rd "$B137" 'everUsed()(bool)')" "everUsed flipped"
eq "true" "$(rd "$B137" 'configSealed()(bool)')" "configSealed flipped too -- _markUsed(), which does NOT revoke DEFAULT_ADMIN"
probe="$(cast call "$B137" 'setInbound(uint256,address,address,uint8,uint256,bool)' 724 "$LXON724" "$WLXON" 2 "$(w "$AMT * 2")" true --from "$ADMIN137" --rpc-url "$F137" 2>&1 | head -1)"
case "$probe" in *"not configured yet"*|*revert*) ok "and now the admin's own setInbound is refused ($(printf '%s' "$probe" | cut -c1-70)) -- the cap raise had to come BEFORE the first claim" ;; *) bad "setInbound still accepted by the admin after the seal: $probe" ;; esac

printf '\n== step 4: a legacy holder migrates against the funded reserve\n'
H_LEG_BEFORE="$(rd "$LEG" 'balanceOf(address)(uint256)' "$HOLDER" | awk '{print $1}')"
fund "$F137" "$HOLDER" 100000000000000000000
send "$F137" "$HOLDER" "$LEG" 'approve(address,uint256)' "$PM" "$AMT" >/dev/null
h_m="$(send "$F137" "$HOLDER" "$PM" 'migrate(uint256)' "$AMT")"
eq "0x1" "$(rpc "$F137" eth_getTransactionReceipt "[\"$h_m\"]" | field status)" "migrate() mined against a real reserve"
say "gasUsed: migrate() on 137 = $(rpc "$F137" eth_getTransactionReceipt "[\"$h_m\"]" | field gasUsed)"
eq "0" "$(rd "$PM" 'reserveBalance()(uint256)' | awk '{print $1}')" "the reserve is spent: a $TRANCHE tranche backs exactly $TRANCHE of conversion and no more"
eq "$AMT" "$(rd "$WLXON" 'balanceOf(address)(uint256)' "$HOLDER" | awk '{print $1}')" "the holder received new wLXON 1:1"
eq "$AMT" "$(rd "$LEG" 'balanceOf(address)(uint256)' "$DEAD" | awk '{print $1}')" "their legacy went to 0xdead"
eq "$(w "$H_LEG_BEFORE - $AMT")" "$(rd "$LEG" 'balanceOf(address)(uint256)' "$HOLDER" | awk '{print $1}')" "the holder paid out the tranche in legacy -- 4,010,000 became $(w "($H_LEG_BEFORE - $AMT) // $E18"), and the rest cannot convert until more LXON crosses"
eq "4010000000001000000000000" "$(rd "$LEG" 'totalSupply()(uint256)' | awk '{print $1}')" "legacy totalSupply UNCHANGED -- the holder's legacy was moved to 0xdead, not burned"
short="$(cast call "$PM" 'migrate(uint256)' "$E18" --from "$HOLDER" --rpc-url "$F137" 2>&1 | head -1)"
# Probed as the same holder, who still owns ~3,910,000 legacy: as an empty-holder address this would
# revert for the wrong reason ("nothing to migrate") and the check would pass without proving the
# reserve is what ran out.
case "$short" in *InsufficientReserve*|*revert*) ok "the next unit for that holder reverts for want of reserve: $(printf '%s' "$short" | cut -c1-72)" ;; *) bad "migrate() succeeded against an empty reserve: $short" ;; esac
say "legacy still held by that wallet: $(w "$(rd "$LEG" 'balanceOf(address)(uint256)' "$HOLDER" | awk '{print $1}') // $E18") of 4,010,000 -- that is what a single tranche does not cover"

printf '\n== what this produced\n'
say "a $TRANCHE reserve is reachable with: 1 approve + 1 lockTransfer on 724, 1 claimTransfer on 137,"
say "and 2 attestor signatures -- all measured here on the real bytecode."
say "converting ALL 4,010,000 legacy needs 41 of this crossing (40 x 100,000 leaves 10,000 behind --"
say "724's maxTransferAmount is 100,000 and 724 is sealed), OR one 48 h batch on 724 to raise it, and the"
say "137 cap raise must happen before the FIRST claim, because that claim seals 137."
say "also proven: 100% of legacy sits in one wallet, so until that balance moves, every wLXON this"
say "reserve pays out goes to the account whose key is in the git history."
printf '\n'
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1
