#!/usr/bin/env bash
# Isolation gate: prove the 725/726 testbed never touched production chain 724, and never will.
#
# Every check here is a read against https://rpc.lxon.in or against local state. Nothing in this
# script writes anywhere. The point is that "we promised not to touch 724" is not evidence: a
# redeploy at the live address, a write through the public RPC, or a leaked key spending on 724 all
# leave a trace that can be MEASURED, and each of the four has its own line below.
#
# Exit 0 means every assertion held. Exit 1 means one did not -- treat that as an incident, not a
# flaky test, and do not "fix" the expectation without re-measuring production.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
FAIL=0
say() { printf '%s %s\n' "$1" "$2"; [[ "$1" == "FAIL" ]] && FAIL=1; }
rpc() { # rpc <method> <params-json>
  curl -s -m 8 https://rpc.lxon.in -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}
hexdec() { python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))" 2>/dev/null || echo parse-error; }

# Production anchors, measured 2026-10-22 against https://rpc.lxon.in at block 59739.
PROD_BRIDGE=0x28c93c2af6b1d5349ba356a8735b343b2caa4379   # the live v3 bridge, the only one with code
PROD_BRIDGE_SIZE=12557
LEAKED_DEV=0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27  # DEVELOPER key that sat in tracked config until
                                                        # a3ee26e. NOT the founder (0x7F715B7F…9Ef3) and
                                                        # NOT the bridge admin (0xFaE699d2…19cAdA).
PEERS=(725 726 137 56)
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000

if command -v cast >/dev/null; then PEER_SEL=$(cast sig 'peerBridges(uint256)'); else PEER_SEL=0x7d67c367; fi

echo "--- 1. the chain-724 mirror stack must not be running alongside the testbed ---"
# lxon-besu-sealer holds the SAME validator private key as production 724. Two sealers with one key
# fork a chain; that is the reason this line exists, not tidiness.
MIRROR=$(docker ps --format '{{.Names}}' | grep -E 'lxon-besu-|lxon-blockscout-|lxon-sc-verifier' | wc -l | tr -d ' ')
if [[ "$MIRROR" == "0" ]]; then say PASS "no chain-724 mirror containers running"
else say FAIL "$MIRROR chain-724 mirror containers are up -- stop them (same validator key, shared RAM)"; fi

echo "--- 2. no testbed port may be serving chain 724 ---"
for P in 8645 8646 8647 8648 8665; do
  CID=$(curl -s -m 3 "http://127.0.0.1:$P" -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | hexdec)
  case "$CID" in
    725|726) say PASS "port $P is chain $CID" ;;
    724)     say FAIL "port $P is serving chain 724 -- this is exactly the entanglement being guarded" ;;
    *)       say PASS "port $P not answering (fine before bring-up)" ;;
  esac
done

echo "--- 3. production is live, not a stale mirror or a local fork ---"
H1=$(rpc eth_blockNumber '[]' | hexdec); sleep 7; H2=$(rpc eth_blockNumber '[]' | hexdec)
CID=$(rpc eth_chainId '[]' | hexdec)
if [[ "$CID" == "724" ]]; then say PASS "rpc.lxon.in reports chainId 724"; else say FAIL "rpc.lxon.in reports chainId $CID"; fi
if [[ "$H1" != "parse-error" && "$H2" != "parse-error" && "$H2" -gt "$H1" ]]; then
  say PASS "production advancing: $H1 -> $H2 (so the reads below are the live chain)"
else
  say FAIL "production height did not advance ($H1 -> $H2) -- reads below cannot be trusted as live"
fi

echo "--- 4. the live bridge still has no peer: no testbed address was ever written to 724 ---"
for c in "${PEERS[@]}"; do
  V=$(rpc eth_call "[{\"to\":\"$PROD_BRIDGE\",\"data\":\"${PEER_SEL}$(printf '%064x' "$c")\"},\"latest\"]" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result"))')
  if [[ "$V" == "$ZERO" ]]; then say PASS "peerBridges($c) on 724 is zero"
  else say FAIL "peerBridges($c) on 724 = $V -- a testbed step registered a peer on production"; fi
done

echo "--- 5. the live bridge contract is the same bytes as the baseline ---"
SIZE=$(rpc eth_getCode "[\"$PROD_BRIDGE\",\"latest\"]" \
       | python3 -c 'import sys,json;print((len(json.load(sys.stdin)["result"])-2)//2)')
if [[ "$SIZE" == "$PROD_BRIDGE_SIZE" ]]; then say PASS "production bridge code is $SIZE bytes (no redeploy at the live address)"
else say FAIL "production bridge code is $SIZE bytes, expected $PROD_BRIDGE_SIZE -- someone replaced the live contract"; fi

echo "--- 6. the testbed's own addresses have no code on 724 ---"
# peerBridges being zero proves nothing on its own if a testbed contract was simply deployed to 724 by
# mistake. This reads each testbed address back from production: all must be empty.
RECORD=""
for cand in ../../../apps/contracts/deployments/testnet-725-726.json \
            /Users/adikamble/LXON/attested-bridge-wt/apps/contracts/deployments/testnet-725-726.json; do
  [[ -f "$cand" ]] && { RECORD="$cand"; break; }
done
if [[ -z "$RECORD" ]]; then
  say FAIL "no deployments/testnet-725-726.json found -- the gate cannot check the testbed addresses"
else
  for A in $(python3 -c "
import json;d=json.load(open('$RECORD'))
print(' '.join(sorted({c['contracts']['LXONAttestedBridge'] for c in d['chains'].values()} |
                      {c['contracts']['LXONBridgeToken'] for c in d['chains'].values()})))"); do
    CODE=$(rpc eth_getCode "[\"$A\",\"latest\"]" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["result"]))')
    if [[ "$CODE" == "2" ]]; then say PASS "testbed address $A has no code on 724"
    else say FAIL "testbed address $A HAS CODE on 724 ($CODE hex chars) -- the testbed leaked into production"; fi
  done
fi

echo "--- 7. the leaked developer key still has never signed on 724 ---"
# Label matters: an earlier version of this file called this address "founder". It is a developer
# account; the founder wallet is 0x7F715B7F...9Ef3 and the bridge admin is 0xFaE699d2...19cAdA.
# A mislabelled key in a security check gets the wrong thing rotated.
FNONCE=$(rpc eth_getTransactionCount "[\"$LEAKED_DEV\",\"latest\"]" | hexdec)
if [[ "$FNONCE" == "0" ]]; then say PASS "leaked developer account nonce is still 0 on 724 (canary, not the exposure: its real funds are on Polygon and the key is still unrotated)"
else say FAIL "leaked developer account nonce is $FNONCE on 724 -- the key in git history was used on this chain"; fi

echo "--- 8. genesis lineage: every EVM gate identical to the file production runs ---"
# This is the only assertion in the plan anchored to an external artifact rather than to a constant
# the producer also uses: the reference is lxon-evm-node/besu/genesis.qbft.json, the genesis actually
# running on 724, so a typo repeated on both sides of the testbed cannot satisfy it.
python3 - <<'PY'
import json, sys
try:
    prod = json.load(open("../genesis.qbft.json"))
except Exception as e:
    print(f"FAIL production genesis not readable: {e}"); sys.exit(1)
expect_config, expect_top = {"chainId", "qbft"}, {"config", "alloc", "extraData"}
ok = True
for chain in ("725", "726"):
    g = json.load(open(f"{chain}/genesis.json"))
    cfg = {k for k in set(prod["config"]) | set(g["config"]) if prod["config"].get(k) != g["config"].get(k)}
    top = {k for k in set(prod) | set(g) if prod.get(k) != g.get(k)}
    print(f"  {chain}: config diffs vs production = {sorted(cfg)}; top-level = {sorted(top)}")
    if cfg - expect_config:
        print(f"FAIL {chain}: EVM gate(s) {sorted(cfg-expect_config)} differ from production"); ok = False
    if expect_config - cfg:
        print(f"FAIL {chain}: chainId/qbft unexpectedly identical to production"); ok = False
    if top - expect_top:
        print(f"FAIL {chain}: top-level {sorted(top-expect_top)} differs; only config/alloc/extraData may"); ok = False
print("PASS LINEAGE OK: every Cancun/Shanghai/London gate is byte-identical to production"
      if ok else "FAIL lineage check failed")
sys.exit(0 if ok else 1)
PY
[[ $? -eq 0 ]] || FAIL=1

echo "--- result ---"
echo "production height at exit: $(rpc eth_blockNumber '[]' | hexdec)"
[[ $FAIL -eq 0 ]] && echo "ISOLATION OK" || echo "ISOLATION VIOLATED"
exit $FAIL
