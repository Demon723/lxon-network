#!/usr/bin/env python3
"""The checking half of the *EIP-1559* offline signing split (Polygon 137), in one place on purpose.

This is the sibling of `offline_plan.py`. It exists separately because 724 is a legacy-gas chain and
137 is EIP-1559, and the two decode shapes differ: a legacy transaction reports `gasPrice`, an EIP-1559
transaction reports `maxFeePerGas` and `maxPriorityFeePerGas` and NO `gasPrice` (measured 2026-10-26:
`cast mktx --gas-price <maxFee> --priority-gas-price <tip>` produces a 0x02-type transaction whose
`cast decode-transaction` output has keys `maxFeePerGas`/`maxPriorityFeePerGas` and no `gasPrice`).
Editing the legacy file to handle both would risk the path that deployed the 724 bridge; a separate
lane keeps that file frozen. The cost is a second file, and the rule that justified it is unchanged:
Sign137Plan.sh and Broadcast137Signed.sh call THIS file, so the two halves of one ceremony can never
drift from each other the way two independent implementations would.

Stdin/stdout only, no network, no keys. `verify` decodes a signed transaction; decoding needs no
secret, which is the entire reason the split is safe to run.
"""
import json
import os
import subprocess
import sys


def plan(path):
    with open(os.path.join(path, "plan.json")) as fh:
        return json.load(fh)


def num(x):
    """Accept '0x2a', '42' and '42 [1e21]' -- cast's own numeric suffix has broken string compares.

    Decimal text is parsed as an int, never through float: a wei amount is a 64+ bit integer and
    `int(float("13358697472847208132"))` returns 13358697472847208448 -- the float64 mantissa holds 53
    bits. That made the verifier reject a *correct* payable signature ("value is 0xb963a092faf75ec4, plan
    says 13358697472847208132", which are the same number), and it hid because round values like 1e18 are
    exactly representable. Powers of ten pass a float round trip; a measured gas reserve never does.
    """
    if isinstance(x, str):
        x = x.strip().split()[0]
        if x.startswith("0x") or x.startswith("0X"):
            return int(x, 16)
        try:
            return int(x)
        except ValueError:
            return int(float(x))     # only for genuinely fractional text like "1.5e3"
    return int(x)


def decode(raw_hex):
    out = subprocess.run(["cast", "decode-transaction", raw_hex], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("cast decode-transaction failed: " + (out.stderr or out.stdout)[:200])
    d = json.loads(out.stdout)
    if isinstance(d, str):          # this cast prints the decoded tx as a JSON *string*
        d = json.loads(d)
    return d


def compare(d, expect):
    """Return [] when the signature says what the plan says; otherwise the list of differences.

    Fee fields are checked as the EIP-1559 pair. If a decoded transaction is legacy (has gasPrice,
    no maxFeePerGas) that is itself the error: the plan authorises 1559 and a legacy signature for a
    137 launch would not carry the priority fee the base fee demands.
    """
    bad = []
    if "type" in d and num(d["type"]) != 2:
        bad.append("transaction type is %s, a 137 launch plan requires EIP-1559 (type 2)" % d["type"])
    if "maxFeePerGas" not in d:
        bad.append("decoded transaction has no maxFeePerGas -- it is not an EIP-1559 transaction, "
                   "so it was not signed with the plan's --gas-price/--priority-gas-price pair")
    for field in ("nonce", "value", "gas", "chainId"):
        if field in expect and num(d[field]) != num(expect[field]):
            bad.append("%s is %s, plan says %s" % (field, d[field], expect[field]))
    for field in ("maxFeePerGas", "maxPriorityFeePerGas"):
        if field in expect:
            if field not in d:
                bad.append("%s missing from the signed transaction" % field)
            elif num(d[field]) != num(expect[field]):
                bad.append("%s is %s, plan says %s" % (field, d[field], expect[field]))
    got_to = d.get("to") or "0x"
    if "to" in expect and got_to.lower() != str(expect["to"]).lower():
        bad.append("destination is %s, plan says %s" % (got_to, expect["to"]))
    if "data" in expect and d["input"].lower() != str(expect["data"]).lower():
        bad.append("calldata differs from the plan (%d hex vs %d)" % (len(d["input"]), len(expect["data"])))
    if "from" in expect and d["signer"].lower() != str(expect["from"]).lower():
        bad.append("signer is %s, plan is for %s" % (d["signer"], expect["from"]))
    if "hash" in expect and d["hash"].lower() != str(expect["hash"]).lower():
        bad.append("hash is %s, expected %s" % (d["hash"], expect["hash"]))
    return bad


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""

    if cmd == "txs":
        # label nonce to value data gas maxFee priority -- eight tab-separated columns.
        for t in plan(os.environ["PLAN_DIR"])["txs"]:
            print("\t".join([t["label"], str(t["nonce"]), t["to"], str(t["value"]),
                             t["data"], str(t["gas"]), str(t["maxFeePerGas"]),
                             str(t["maxPriorityFeePerGas"])]))
        return 0

    if cmd == "field":
        p = plan(os.environ["PLAN_DIR"])
        v = p.get(sys.argv[2])
        if v is None:
            return 0
        print(" ".join(str(x) for x in v) if isinstance(v, list) else v)
        return 0

    if cmd == "verify":
        # A signed transaction is authorisation to move money. Verify it against the plan before it is
        # broadcast -- and before it is handed over, on the key host, where a mismatch is still free.
        path = sys.argv[2]
        raw = open(path).read().strip()
        if not raw.startswith("0x"):
            raw = "0x" + raw
        expect = {"nonce": sys.argv[3], "to": sys.argv[4], "value": sys.argv[5], "data": sys.argv[6],
                  "gas": sys.argv[7], "maxFeePerGas": sys.argv[8], "maxPriorityFeePerGas": sys.argv[9],
                  "chainId": sys.argv[10], "from": sys.argv[11]}
        bad = compare(decode(raw), expect)
        if bad:
            print("; ".join(bad))
            return 1
        print("OK")
        return 0

    if cmd == "hash":
        # A leading "0x" is a prefix; a leading "0" is the type byte of an EIP-1559 transaction.
        # `raw.lstrip("0x")` strips both, which turned `02f8…` into `2f8…` and made the broadcaster die
        # on its own hash recovery -- measured here, and invisible to the 724 legacy path because a
        # legacy RLP encoding never begins with a zero nibble.
        raw = open(sys.argv[2]).read().strip()
        if raw[:2] in ("0x", "0X"):
            raw = raw[2:]
        print(decode("0x" + raw)["hash"])
        return 0

    if cmd == "receipt":
        raw = sys.stdin.read().strip()
        try:
            d = json.loads(raw)
        except ValueError:
            return 0
        # `cast rpc` prints the bare JSON-RPC *result*, not the envelope -- so a receipt arrives as
        # {"status": "0x1", ...}. Unwrapping a "result" key that is never there is how a mined
        # transaction reads as "not mined", which is the worst possible thing for a broadcaster to
        # believe. Accept either shape rather than betting on one.
        if isinstance(d, dict) and "result" in d:
            d = d["result"]
        if not isinstance(d, dict):
            return 0
        print(d.get(sys.argv[2]) or "")
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
