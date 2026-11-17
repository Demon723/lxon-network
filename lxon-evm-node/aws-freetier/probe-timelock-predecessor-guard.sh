#!/usr/bin/env bash
# Does the deployed 137 timelock (0xe56553Ed…, 5,448 B) enforce the predecessor requirement, and with
# which error? Its runtime bytecode has no PUSH4 for TimelockUnexecutedPredecessor(bytes32) (0x90a9a618)
# although upstream OZ v5.0.0 and v5.7.0 both declare and use it.
#
# FIRST ATTEMPT, WRONG, KEPT HERE ON PURPOSE: the obvious probe was "schedule a zero-predecessor batch,
# then call executeBatch with a non-zero predecessor". That tests nothing, because hashOperationBatch
# mixes the predecessor into the operation id -- swapping it produces a *different operation id* that
# was never scheduled, so the very first check (!isOperationReady(id)) fires first and you read a
# predecessor-revert that is really an unscheduled-op revert. The tell was that the reverted id did not
# equal the id we scheduled.
#
# CORRECT ISOLATION: chain two real operations.
#   opA = batch(salt A, predecessor 0)      -> schedule, wait out the delay  -> Ready
#   opB = batch(salt B, predecessor idA)    -> schedule, wait out the delay  -> Ready
# Now executeBatch(opB) passes the Ready check on its own id, so the only guard left standing is the
# predecessor one -- idA is Ready, and the predecessor rule wants Done. Whatever comes back is the
# deployed contract's own answer to the question actually asked.
#
# Everything happens on a local anvil fork. Nothing is signed; nothing reaches a real chain.
set -uo pipefail

TL=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5
BR=0xbDC32d8Ca8Ce805E0654e7A7d0DD1eE0A21D4a95
PROP=0x2a8Ca01C53cecF360b181a0B7D49a71565684665
PORT=18548
UPSTREAM="${UPSTREAM:-https://polygon.drpc.org}"
die() { echo "ABORT: $*" >&2; exit 1; }

lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1 && die "port $PORT busy -- a leftover anvil would hand this probe its state AND its clock"
anvil --fork-url "$UPSTREAM" --chain-id 137 --port $PORT >/tmp/tlprobe2.anvil.log 2>&1 &
ANVIL=$!
trap 'kill "$ANVIL" 2>/dev/null' EXIT
for _ in $(seq 1 40); do cast rpc eth_chainId --rpc-url http://127.0.0.1:$PORT >/dev/null 2>&1 && break; sleep 1; done
kill -0 "$ANVIL" 2>/dev/null || die "anvil died; see /tmp/tlprobe2.anvil.log"
F="http://127.0.0.1:$PORT"
[ "$(cast chain-id --rpc-url $F)" = "137" ] || die "fork is not chain 137"

HT=$(cast rpc eth_getBlockByNumber latest false --rpc-url $F 2>/dev/null \
     | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d.get("result",d);print(int(d["timestamp"],16))')
NOW=$(date -u +%s)
python3 -c 'import sys;sys.exit(0 if abs(int(sys.argv[1])-int(sys.argv[2]))<600 else 1)' "$HT" "$NOW" \
  || die "fork head $HT not within 600 s of wall clock $NOW"
echo "fork: chain 137, head $HT ($((NOW-HT)) s behind wall clock), upstream $UPSTREAM"

cast rpc anvil_impersonateAccount "$PROP" --rpc-url $F >/dev/null
cast rpc anvil_setBalance "$PROP" 0x8ac7230489e80000 --rpc-url $F >/dev/null 2>&1
GOT=$(cast rpc eth_getBalance "$PROP" latest --rpc-url $F 2>&1)
python3 -c 'import sys;sys.exit(0 if int(sys.argv[1],16)>=10**19 else 1)' "$(printf '%s' "${GOT:-0x0}" | tr -dc '0-9a-fA-Fx')" \
  || die "could not fund the impersonated proposer"

P="[$BR,$BR,$BR]"; V="[0,0,0]"; D="[0xdeadbeef,0xcafebabe,0xfeedface]"
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000
SALT_A=$(cast keccak "lxon-timelock-probe:opA:v2")
SALT_B=$(cast keccak "lxon-timelock-probe:opB:v2")
SIG="executeBatch(address[],uint256[],bytes[],bytes32,bytes32)"
HS="hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)"
SB="scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)"

ID_A=$(cast call $TL "$HS" "$P" "$V" "$D" "$ZERO" "$SALT_A" --rpc-url $F)
echo
echo "opA id (predecessor 0)      = $ID_A"
cast send $TL "$SB" "$P" "$V" "$D" "$ZERO" "$SALT_A" 172800 --rpc-url $F --unlocked --from "$PROP" --json >/dev/null \
  || die "schedule opA failed"
cast rpc evm_increaseTime 172801 --rpc-url $F >/dev/null && cast rpc evm_mine --rpc-url $F >/dev/null
printf '  opA getOperationState     = ' "$(printf %s)" ""; cast call $TL "getOperationState(bytes32)(uint8)" "$ID_A" --rpc-url $F
echo "  ^ 2 = Ready"

ID_B=$(cast call $TL "$HS" "$P" "$V" "$D" "$ID_A" "$SALT_B" --rpc-url $F)
echo
echo "opB id (predecessor opA)    = $ID_B"
echo "  note it differs from opA's id because the predecessor is hashed INTO the id -- the exact thing"
echo "  that made the single-op probe test the wrong guard"
cast send $TL "$SB" "$P" "$V" "$D" "$ID_A" "$SALT_B" 172800 --rpc-url $F --unlocked --from "$PROP" --json >/dev/null \
  || die "schedule opB failed (scheduling behind a non-Ready predecessor is refused by design)"
cast rpc evm_increaseTime 172801 --rpc-url $F >/dev/null && cast rpc evm_mine --rpc-url $F >/dev/null
printf '  opB getOperationState     = '; cast call $TL "getOperationState(bytes32)(uint8)" "$ID_B" --rpc-url $F
echo "  ^ 2 = Ready. opA is still 2 (Ready), NOT 3 (Done) -- so opB's predecessor requirement is unmet"

echo
echo "=== THE PROBE: executeBatch(opB). Its own Ready check passes; only the predecessor guard is left. ==="
cast call $TL "$SIG" "$P" "$V" "$D" "$ID_A" "$SALT_B" --from "$PROP" --rpc-url $F 2>&1 | head -6

echo
echo "=== CONTROL 1: executeBatch(opB) with predecessor 0 -- a DIFFERENT op that was never scheduled ==="
echo "  must revert with the op's OWN id in the first argument, proving which check fires"
cast call $TL "$SIG" "$P" "$V" "$D" "$ZERO" "$SALT_B" --from "$PROP" --rpc-url $F 2>&1 | head -4

echo
echo "=== CONTROL 2: executeBatch(opA) -- Ready, predecessor 0, so the guard cannot apply ==="
echo "  expected: get past both timelock checks and fail inside the bridge call (FailedCall) on dummy calldata"
cast call $TL "$SIG" "$P" "$V" "$D" "$ZERO" "$SALT_A" --from "$PROP" --rpc-url $F 2>&1 | head -4

echo
echo "=== CONTROL 3: prove the guard is a Done-requirement by SATISFYING it ==="
echo "  opC carries harmless payloads (the bridge's own view paused(), selector 0x5c975abb) so executing"
echo "  it SUCCEEDS and marks it Done. opD sits behind opC. If the guard is real, opD flips from refused"
echo "  to legal exactly when opC becomes Done -- and opA's FailedCall roll-back above shows the converse."
PH="[0x5c975abb,0x5c975abb,0x5c975abb]"
SALT_C=$(cast keccak "lxon-timelock-probe:opC:v2")
SALT_D=$(cast keccak "lxon-timelock-probe:opD:v2")
ID_C=$(cast call $TL "$HS" "$P" "$V" "$PH" "$ZERO" "$SALT_C" --rpc-url $F)
cast send $TL "$SB" "$P" "$V" "$PH" "$ZERO" "$SALT_C" 172800 --rpc-url $F --unlocked --from "$PROP" --json >/dev/null || die "schedule opC failed"
ID_D=$(cast call $TL "$HS" "$P" "$V" "$PH" "$ID_C" "$SALT_D" --rpc-url $F)
cast send $TL "$SB" "$P" "$V" "$PH" "$ID_C" "$SALT_D" 172800 --rpc-url $F --unlocked --from "$PROP" --json >/dev/null \
  || die "schedule opD failed"
cast rpc evm_increaseTime 172801 --rpc-url $F >/dev/null && cast rpc evm_mine --rpc-url $F >/dev/null
echo "  opC id $ID_C   opD id $ID_D   (both Ready now; opC is Waiting->Done only if its call succeeds)"
printf '  BEFORE: opD with unmet predecessor -> '; cast call $TL "$SIG" "$P" "$V" "$PH" "$ID_C" "$SALT_D" --from "$PROP" --rpc-url $F 2>&1 | head -2
echo
printf '  executing opC: '; cast send $TL "$SIG" "$P" "$V" "$PH" "$ZERO" "$SALT_C" --rpc-url $F --unlocked --from "$PROP" >/dev/null 2>&1 && echo "mined" || echo "REVERTED"
printf '  opC getOperationState now = '; cast call $TL "getOperationState(bytes32)(uint8)" "$ID_C" --rpc-url $F
echo "  ^ 3 = Done"
printf '  AFTER:  opD with satisfied predecessor -> '; cast call $TL "$SIG" "$P" "$V" "$PH" "$ID_C" "$SALT_D" --from "$PROP" --rpc-url $F 2>&1 | head -2
echo "  ^ success (empty return) means the predecessor guard was the only thing refusing it before"

echo
echo "=== deployed runtime, re-checked (fork copy must equal live) ==="
CODE=$(cast code $TL --rpc-url $F)
python3 - "$CODE" <<'PYEOF'
import sys
h = sys.argv[1].strip()[2:]
b = bytes.fromhex(h)
print(f"  runtime bytes: {len(b)}")
for name, sel in (("TimelockUnexecutedPredecessor(bytes32)","90a9a618"),
                  ("TimelockUnexpectedOperationState(bytes32,bytes32)","5ead8eb5"),
                  ("FailedCall()","d6bda275")):
    print(f"  {sel}  {name:46} substring={'YES' if sel in h else 'no '}  PUSH4={'YES' if any(b[i]==0x63 and b[i+1:i+5].hex()==sel for i in range(len(b))) else 'no'}")
PYEOF
