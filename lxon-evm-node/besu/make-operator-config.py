#!/usr/bin/env python3
"""Regenerate besu/operator-config.json for the QBFT dev chain.

Reads the existing sealer private key, derives its *public* key (a public value) and
writes it into the operator config so that `besu operator generate-blockchain-config`
RLP-encodes the genesis extraData with our validator address. Never prints the key.
"""
import json
import os
import sys

KEY_PATH = "/Users/adikamble/lxon/LXON/lxon-evm-node/geth/privatekey.txt"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "operator-config.json")
SEALER = "fae699d2848957c7c3be67d8c90f0e456419cada"
BALANCE = "0x1337000000000000000000000000000000000000000000000000000000000000"

raw = open(KEY_PATH).read().strip()
assert len(raw) == 64, "unexpected private key file format"
from eth_keys import keys  # noqa: E402

pub = keys.PrivateKey(bytes.fromhex(raw)).public_key
addr = pub.to_checksum_address()
assert addr.lower() == "0x" + SEALER, f"key mismatch: {addr}"

config = {
    "blockchain": {"nodes": {"generate": False, "keys": [pub.to_hex()]}},
    "genesis": {
        "alloc": {SEALER: {"balance": BALANCE}},
        "coinbase": "0x0000000000000000000000000000000000000000",
        "config": {
            "chainId": 724,
            "homesteadBlock": 0,
            "eip150Block": 0,
            "eip155Block": 0,
            "eip158Block": 0,
            "byzantiumBlock": 0,
            "constantinopleBlock": 0,
            "petersburgBlock": 0,
            "istanbulBlock": 0,
            "berlinBlock": 0,
            "londonBlock": 0,
            "shanghaiTime": 0,
            "cancunTime": 0,
            "qbft": {
                "blockperiodseconds": 5,
                "epochlength": 30000,
                "requesttimeoutseconds": 10,
            },
        },
        "difficulty": "0x1",
        "extraData": "0x",
        "gasLimit": "0x1c9c380",
        "gasUsed": "0x0",
        "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "nonce": "0x0",
        "number": "0x0",
        "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "timestamp": "0x655c0000",
    },
}

with open(OUT, "w") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\n")
print(f"wrote {OUT}  (sealer {addr})")
