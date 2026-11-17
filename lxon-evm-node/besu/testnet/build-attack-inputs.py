#!/usr/bin/env python3
"""Build the inputs for replay-attacks.sh out of live chain state.

Nothing here is typed from memory: the two fresh locks are made now, their claimIds are taken from
the TransferLocked log (matched on topic0, because receipt log 0 is the ERC-20 Transfer and its
topics[1] is the sender address), and every request tuple is decoded from that log's data. The
signatures come from attest.py against the destination bridge's own claimDigest().

Emits, under /tmp:
  attack_req.txt          the transfer Task 12 already credited on 726 (attack 1, 2, 3, 4)
  attack_sigs.txt         its 3-signature quorum bundle
  attack_sigs_two.txt     the same bundle with only two signatures
  attack_req_over.txt     the same request with amount raised and the attested total left alone
  attack_l4_req.txt       a fresh, never-claimed transfer for the ascending-order attack
  attack_l4_sigs_rev.txt  its bundle, deliberately reversed
  attack_l2_*.txt         the two consecutive transfers used for the gapless/reorder attack
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RPC725, RPC726 = "http://127.0.0.1:8645", "http://127.0.0.1:8665"
LOCKED_TOPIC = "0xffbcdf51b19ce9c36136ee0c2bec9cbf3c9f0f8b459f9174e992e0c850d11c28"
FT = "claimTransfer((uint256,uint256,uint256,uint256,address,uint256,address,address,uint256),bytes[])"
FIELDS = ["srcChainId", "nonce", "srcTotalSent", "destChainId", "srcToken",
          "amount", "sender", "recipient", "srcBlock"]

env = json.load(open("/tmp/env.json"))
PK = open(os.path.join(HERE, "keys", "deployer.hex")).read().strip()


def sh(*a):
    return subprocess.run([str(x) for x in a], capture_output=True, text=True)


def cast_send(to, sig, *args):
    r = sh("cast", "send", to, sig, *args, "--rpc-url", RPC725, "--private-key", PK, "--json")
    try:
        d = json.loads(r.stdout)
    except Exception:
        sys.exit(f"cast send failed to parse: {r.stdout[:200]} {r.stderr[:200]}")
    if d.get("success") is False:
        sys.exit(f"cast send reverted: {json.dumps(d.get('errors'))[:300]}")
    return d


def request_from_receipt(d):
    """Return (claimId, tuple-string, decoded dict) for the TransferLocked log in this receipt."""
    m = [l for l in d["logs"] if l["topics"][0].lower() == LOCKED_TOPIC]
    if len(m) != 1:
        sys.exit(f"expected exactly one TransferLocked, got {len(m)}")
    lg = m[0]
    raw = lg["data"]
    words = [raw[2:][i:i + 64] for i in range(0, len(raw) - 2, 64)]
    if len(words) != 9:
        sys.exit(f"TransferLocked carries 9 words, got {len(words)}")
    vals = [("0x" + w[-40:]) if f in ("srcToken", "sender", "recipient") else str(int(w, 16))
            for f, w in zip(FIELDS, words)]
    dec = dict(zip(FIELDS, vals))
    # Cross-check every decoded field against something independent of the decode itself.
    assert dec["srcChainId"] == "725" and dec["destChainId"] == "726", dec
    assert dec["sender"].lower() == env["DEPLOYER"].lower(), dec
    assert dec["recipient"].lower() == env["RECIPIENT"].lower(), dec
    assert dec["srcToken"].lower() == env["NATIVE725"].lower(), dec
    assert int(dec["srcBlock"]) == int(lg["blockNumber"], 16), (dec["srcBlock"], lg["blockNumber"])
    return lg["topics"][1], "(" + ",".join(vals) + ")", dec


def bundle(claim_id):
    r = sh("python3", os.path.join(HERE, "attest.py"), "--claim", claim_id,
           "--rpc", RPC726, "--bridge", env["BRIDGE726"])
    if r.returncode:
        sys.exit(f"attest.py failed: {r.stderr[:300]}")
    b = json.loads(r.stdout)
    assert len(b["signatures"]) == 4, "expected four validator signatures"
    return b["signatures"][:3]


def lock(amount):
    """Lock on 725 and prove the source total moved by exactly `amount`.

    The expectation is chained off the on-chain total rather than off Task 12's value, so this stays
    true on a second sweep: the first run's transfers are already inside the running total, and an
    assert written against 500e18 fails for reasons that have nothing to do with the bridge.
    """
    before = int(sh("cast", "call", env["BRIDGE725"], "totalSentFor(uint256)(uint256)", 726,
                    "--rpc-url", RPC725).stdout.split()[0])
    d = cast_send(env["BRIDGE725"], "lockTransfer(address,uint256,uint256,address)",
                  env["NATIVE725"], amount, 726, env["RECIPIENT"])
    cid, req, dec = request_from_receipt(d)
    assert int(dec["srcTotalSent"]) == before + amount, (before, amount, dec["srcTotalSent"])
    return cid, req, dec


def write(name, text):
    open(f"/tmp/{name}", "w").write(text)


# --- the transfer Task 12 already credited: rebuild its tuple from the ORIGINAL lock receipt ---
orig = json.load(open("/tmp/lock.json"))
claim1, req1, dec1 = request_from_receipt(orig)
sigs1 = bundle(claim1)
write("attack_req.txt", req1)
write("attack_sigs.txt", "[" + ",".join(sigs1) + "]")
write("attack_sigs_two.txt", "[" + ",".join(sigs1[:2]) + "]")
over = list(dec1.values())
over[5] = str(int(dec1["amount"]) + 10 ** 21)          # amount up, attested total NOT up
write("attack_req_over.txt", "(" + ",".join(over) + ")")

# --- three fresh transfers: L2 and L3 are consecutive, L4 stays unclaimed for the order attack ---
l2 = lock(100 * 10 ** 18)
l3 = lock(100 * 10 ** 18)
l4 = lock(100 * 10 ** 18)
for tag, (cid, req, dec) in (("l2", l2), ("l3", l3), ("l4", l4)):
    s = bundle(cid)
    write(f"attack_{tag}_id.txt", cid)
    write(f"attack_{tag}_req.txt", req)
    write(f"attack_{tag}_sigs.txt", "[" + ",".join(s) + "]")
    write(f"attack_{tag}_sigs_rev.txt", "[" + ",".join(reversed(s)) + "]")

print("inputs built from live chain state:")
print("  original credited claimId :", claim1)
print("  L2 (must be claimed first):", l2[0], l2[1])
print("  L3 (claimed out of order) :", l3[0], l3[1])
print("  L4 (never claimed)        :", l4[0], l4[1])
