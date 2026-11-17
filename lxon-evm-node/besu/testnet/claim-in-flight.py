#!/usr/bin/env python3
"""Drain the 725 -> 726 queue: find every TransferLocked on 725 that 726 has not credited, and claim
them in nonce order.

This exists because the gapless-total rule is real. A transfer that was locked but never claimed is
not lost -- it is queued -- and while it sits there every later transfer on that peer fails with
`total mismatch` until the earlier ones are credited first. That is the behaviour under test, so the
tool that works around it has to obey it too: the queue is claimed in ascending nonce order or not at
all.

Requests are decoded from the event data, never retyped; digests come from the destination bridge's
own claimDigest(); signatures come from attest.py. Safe to re-run: anything already credited is
skipped by its ledger status.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RPC725, RPC726 = "http://127.0.0.1:8645", "http://127.0.0.1:8665"
LOCKED_TOPIC = "0xffbcdf51b19ce9c36136ee0c2bec9cbf3c9f0f8b459f9174e992e0c850d11c28"
LOCKED_SIG = ("TransferLocked(bytes32,tuple(uint256,uint256,uint256,uint256,address,"
              "uint256,address,address,uint256))")
FIELDS = ["srcChainId", "nonce", "srcTotalSent", "destChainId", "srcToken",
          "amount", "sender", "recipient", "srcBlock"]
FT = ("claimTransfer((uint256,uint256,uint256,uint256,address,uint256,address,address,uint256)"
      ",bytes[])")

env = json.load(open("/tmp/env.json"))
PK = open(os.path.join(HERE, "keys", "deployer.hex")).read().strip()


def sh(*a):
    return subprocess.run([str(x) for x in a], capture_output=True, text=True)


def decode(data):
    words = [data[2:][i:i + 64] for i in range(0, len(data) - 2, 64)]
    assert len(words) == 9, f"TransferLocked carries 9 words, got {len(words)}"
    vals = [("0x" + w[-40:]) if f in ("srcToken", "sender", "recipient") else str(int(w, 16))
            for f, w in zip(FIELDS, words)]
    return "(" + ",".join(vals) + ")", dict(zip(FIELDS, vals))


def ledger_status(bridge, rpc, claim_id):
    out = sh("cast", "call", bridge, "claims(bytes32)((uint8,uint256,address,uint256))",
             claim_id, "--rpc-url", rpc).stdout.strip()
    if out.startswith("("):
        return int(out[1:].split(",")[0])
    return None


start = sys.argv[1] if len(sys.argv) > 1 else "0x3e8"
logs = json.loads(sh("cast", "logs", "--rpc-url", RPC725, "--from-block", start,
                     "--address", env["BRIDGE725"], LOCKED_SIG, "--json").stdout)
pending = []
for lg in logs:
    if lg["topics"][0].lower() != LOCKED_TOPIC:
        continue
    cid = lg["topics"][1]
    req, dec = decode(lg["data"])
    assert dec["destChainId"] == "726", "this drainer only knows the 725 -> 726 direction"
    if ledger_status(env["BRIDGE726"], RPC726, cid) == 0:
        pending.append((int(dec["nonce"]), cid, req))

pending.sort()
print(f"{len(logs)} TransferLocked events scanned, {len(pending)} unclaimed, "
      f"nonces {[p[0] for p in pending]}")

for nonce, cid, req in pending:
    b = json.loads(sh("python3", os.path.join(HERE, "attest.py"), "--claim", cid,
                      "--rpc", RPC726, "--bridge", env["BRIDGE726"]).stdout)
    sigs = "[" + ",".join(b["signatures"][:3]) + "]"
    r = sh("cast", "send", env["BRIDGE726"], FT, req, sigs, "--rpc-url", RPC726,
           "--private-key", PK, "--json")
    try:
        d = json.loads(r.stdout)
    except Exception:
        sys.exit(f"nonce {nonce}: unparsable response: {r.stdout[:200]} {r.stderr[:200]}")
    print(f"nonce {nonce} claimId {cid[:18]}… status={d.get('status')} tx={d.get('transactionHash')}")
    if d.get("status") != "0x1":
        sys.exit(f"nonce {nonce} failed -- the queue is not drainable in this order: "
                 f"{json.dumps(d.get('errors'))[:300]}")

sent = int(sh("cast", "call", env["BRIDGE725"], "totalSentFor(uint256)(uint256)", 726,
              "--rpc-url", RPC725).stdout.split()[0])
recv = int(sh("cast", "call", env["BRIDGE726"], "totalReceivedFrom(uint256)(uint256)", 725,
              "--rpc-url", RPC726).stdout.split()[0])
print(f"after drain: 725 attested {sent}, 726 credited {recv}, gap {sent - recv}")
