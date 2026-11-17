#!/usr/bin/env python3
"""Collect a validator attestation bundle for a claimId and print it in the order
LXONAttestedBridge requires: ascending recovered address.

Reads validator key files to sign; prints signatures only (they are public once
broadcast). Never prints key bytes. Usage:

  ./attest.py --claim 0x<claimId> --rpc http://127.0.0.1:8665 --bridge 0x<bridge-on-726>

The flags are --rpc and --bridge, not a single --digest-from: the digest is an eth_call to the
DESTINATION bridge, so the url and the address are two different things and the call cannot be
inferred from either one alone.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    out = subprocess.run(["curl", "-s", url, "-H", "content-type: application/json",
                          "-d", body], capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    if "error" in d:
        raise SystemExit(f"RPC error: {d['error']}")
    return d["result"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--claim", required=True, help="claimId (0x…)")
    ap.add_argument("--rpc", required=True, help="destination chain RPC url")
    ap.add_argument("--bridge", required=True, help="destination bridge address")
    ap.add_argument("--keys", default=",".join(os.path.join(HERE, "keys", f"node-{i}.hex") for i in range(1, 5)))
    args = ap.parse_args()

    # claimDigest is a view call, so the digest we sign is provably the one the contract
    # will recompute -- no duplicated EIP-191 logic in this script.
    data = "0x" + subprocess.run(["cast", "sig", "claimDigest(bytes32)"], capture_output=True,
                                  text=True, check=True).stdout.strip()[2:] + \
        args.claim[2:].zfill(64)
    digest = rpc(args.rpc, "eth_call", [{"to": args.bridge, "data": data}, "latest"])

    pairs = []
    for path in args.keys.split(","):
        if not os.path.exists(path):
            continue
        # The key goes to `cast` as a command-line argument, which means it is visible in the
        # process table to any user on this machine for the length of the call. Accepted here
        # because these are throwaway testbed keys with no real value behind them; an operator
        # running this against live keys should use `--account <alias>` against an encrypted
        # keystore instead, which never puts the secret in argv.
        key = open(path).read().strip()
        # `--no-hash` is load-bearing, not a style choice. Measured on cast 1.8.4
        # (`cast wallet sign --help`): a 0x MESSAGE is hex-decoded and then "prefixed with the
        # Ethereum Signed Message header and hashed before signing, unless --no-hash is provided".
        # claimDigest ALREADY contains that header (spec §5.2), so without the flag this signs a
        # double-wrapped hash and recovers an address that is not any validator -- every bundle
        # would fail with "signer not a validator" and look like a key-distribution problem.
        sig = subprocess.run(["cast", "wallet", "sign", "--no-hash", "--private-key", key, digest],
                             capture_output=True, text=True).stdout.strip()
        if not sig.startswith("0x"):
            # `cast wallet sign` may be spelled `cast sign` in this foundry build; verify
            # with `cast wallet --help` before changing this line.
            raise SystemExit(f"signing failed for {os.path.basename(path)}: {sig!r}")
        addr = subprocess.run(["cast", "wallet", "address", "--private-key", key],
                              capture_output=True, text=True).stdout.strip()
        pairs.append((addr.lower(), sig))

    if not pairs:
        raise SystemExit("no key files found; nothing signed")
    pairs.sort(key=lambda p: int(p[0], 16))
    print(json.dumps({
        "digest": digest,
        "signers": [p[0] for p in pairs],
        "signatures": [p[1] for p in pairs],
    }))


if __name__ == "__main__":
    main()
