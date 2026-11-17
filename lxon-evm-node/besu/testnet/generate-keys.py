#!/usr/bin/env python3
"""Generate the throwaway testbed keypairs. Six node keys: nodes 1-4 seal chain 725, node 5 is
the spare Task 3 votes in, and node 6 seals chain 726. Each chain gets its own node identity so
no two running Besu processes can ever present the same key, on any chain. Plus one deployer EOA.

Refuses to run if the files already exist: regenerating would orphan a live blockstore.
Prints addresses only — never key bytes.
"""
import os
import sys

from eth_keys import keys

BASE = os.path.dirname(os.path.abspath(__file__))
KEYS = os.path.join(BASE, "keys")


def write(name, text):
    p = os.path.join(KEYS, name)
    if os.path.exists(p):
        print(f"REFUSING: {p} already exists. Delete it deliberately to rotate keys.", file=sys.stderr)
        sys.exit(1)
    with open(p, "w") as fh:
        fh.write(text)
    os.chmod(p, 0o600)


def main():
    os.makedirs(KEYS, mode=0o700, exist_ok=True)
    # makedirs(exist_ok=True) never chmods a directory it found, and Step 3's mkdir -p created
    # keys/ first, so the mode has to be asserted here or the listing stays world-readable.
    os.chmod(KEYS, 0o700)
    addresses = []
    for i in range(1, 7):
        k = keys.PrivateKey(os.urandom(32))
        write(f"node-{i}.hex", k.to_hex()[2:] + "\n")           # bare 64 hex, Besu's format
        # 0x + 128 hex: eth_keys' PublicKey.to_hex() is the 64 raw bytes WITHOUT the 65-byte
        # 04 prefix. That is the form Besu's operator config wants and the form assert_genesis.py
        # shape-checks; do not add an 04 here when writing an enode/node.json field elsewhere.
        write(f"pub-{i}.hex", k.public_key.to_hex() + "\n")
        addr = "0x" + k.public_key.to_address().removeprefix("0x").lower()
        with open(os.path.join(KEYS, f"address-{i}.txt"), "w") as fh:
            fh.write(addr + "\n")
        addresses.append(addr)
    d = keys.PrivateKey(os.urandom(32))
    write("deployer.hex", d.to_hex()[2:] + "\n")
    daddr = "0x" + d.public_key.to_address().removeprefix("0x").lower()
    with open(os.path.join(KEYS, "deployer-address.txt"), "w") as fh:
        fh.write(daddr + "\n")
    print("generated 6 node keys + 1 deployer key (files, 0600, gitignored)")
    roles = ["725 validator", "725 validator", "725 validator", "725 validator",
             "725 spare (Task 3)", "726 validator"]
    for i, (a, role) in enumerate(zip(addresses, roles), 1):
        print(f"  node-{i}  {a}  {role}")
    print(f"  deployer     {daddr}")


if __name__ == "__main__":
    main()
