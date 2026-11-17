#!/usr/bin/env python3
"""Refresh the public LXON price JSON from the DEX pair reserves + CoinGecko ETH/USD.

Runs on the EC2 node (cron, every 5 min). Reads-only everywhere:
  - reserves: eth_call to the loopback-only sealer RPC (127.0.0.1:8545)
  - ETH/USD: CoinGecko public API
  - output: price.json inside the caddy-data volume, served at /swap/price.json
Writes nothing on-chain and touches no database. On any upstream failure it exits
non-zero and leaves the previous price.json in place (stale but consistent).
"""
import datetime
import json
import os
import urllib.request

RPC = "http://127.0.0.1:8545"
PAIR = "0x272a3ed4b91112005ade5b4161af1adc856ab3f4"
WLXON_PAIR = "0x8e90675e054826f61745c0016b895cdc4f220ebc"  # token0=wLXON, token1=LXON
OUT_DIR = "/var/lib/docker/volumes/lxon-evm_caddy-data/_data/swap"
OUT = os.path.join(OUT_DIR, "price.json")


def rpc_reserves(pair):
    body = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "eth_call",
        "params": [{"to": pair, "data": "0x0902f1ac"}, "latest"],
    }).encode()
    req = urllib.request.Request(RPC, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        result = json.load(r)["result"]
    words = result[2:]  # strip 0x
    r0 = int(words[0:64], 16)    # reserve0
    r1 = int(words[64:128], 16)  # reserve1
    if r0 <= 0 or r1 <= 0:
        raise ValueError("empty reserves")
    return r0, r1


def eth_usd():
    url = "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd"
    with urllib.request.urlopen(url, timeout=10) as r:
        return float(json.load(r)["ethereum"]["usd"])


def main():
    r0, r1 = rpc_reserves(PAIR)
    w0, w1 = rpc_reserves(WLXON_PAIR)
    usd = eth_usd()
    price_eth = r0 / r1  # both 18 decimals; ratio is ETH per LXON
    peg = w1 / w0        # LXON per wLXON from the peg pool (token1/token0)
    payload = {
        "pair": PAIR,
        "reserves": {"weth": str(r0), "lxon": str(r1)},
        "priceLxonInEth": price_eth,
        "ethUsd": usd,
        "priceLxonInUsd": price_eth * usd,
        "updatedAt": datetime.datetime.now(datetime.timezone.utc)
                     .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": "Price derived from the LXON/WETH pool reserves on chain 724. "
                "The pool was seeded by the deployer, so this is a pool-derived "
                "price, not an external market signal.",
        "wlxon": {
            "wrapper": "0xC0CF6B0E6C5a0705F319BA5c629a6Bc7E82FEf00",
            "pair": WLXON_PAIR,
            "router": "0xaa0e4bb075f108b34dc0e279a7747980c76b8d75",
            "reserves": {"wlxon": str(w0), "lxon": str(w1)},
            "pegLxonPerWlxon": peg,
            "priceWlxonInEth": price_eth * peg,
            "priceWlxonInUsd": price_eth * peg * usd,
            "note": "wLXON is escrow-backed 1:1 by LXON in the wrapper "
                    "(supply == collateral, verifiable on chain); the peg pool "
                    "was seeded by the deployer, so the ratio is pool-derived.",
        },
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)
    print(f"{payload['updatedAt']} price={price_eth:.10f} ETH  "
          f"(${price_eth * usd:.6f})  ethUsd={usd}  peg={peg:.6f} LXON/wLXON")


if __name__ == "__main__":
    main()
