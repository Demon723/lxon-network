# price/ — the public LXON price feed

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-05 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x272a3ed4b91112005ade5b4161af1adc856ab3f4` - LXON/WETH pair on 724
> - `0x8e90675e054826f61745c0016b895cdc4f220ebc` - wLXON/LXON peg pair on 724
>
> The control that makes those empty reads evidence, measured by the same script on the same day: the v4.1 bridge on Polygon 137 reads 19105 bytes and wLXON reads 2106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
`price-updater.py` is the script that generates `https://www.lxon.in/swap/price.json` (also served at
`explorer.lxon.in/swap/price.json`). Until 2026-11-01 it existed **only** on the EC2 node at
`/opt/lxon/price-updater.py`, with no source, no history and no test. It was pulled into the repo
byte-for-byte, not rewritten:

```
box  sha256  d836c5a29a4fc841beaac72477bc7dead0e7ee774b5e8c2ec054b63d46d855c9   /opt/lxon/price-updater.py
repo sha256  d836c5a29a4fc841beaac72477bc7dead0e7ee774b5e8c2ec054b63d46d855c9   aws/price/price-updater.py
```

Pulling it in changed nothing on the running system. The copy on the box is still what cron executes;
this file is the reviewable source, and any change to it is a two-step action: edit here, then install
on the node (see `price-crontab`).

## What it does

Read-only, by construction — no key, no signer, no `eth_sendRawTransaction` anywhere in the file:

| step | source |
|---|---|
| LXON/WETH reserves | `eth_call` `getReserves()` (`0x0902f1ac`) to the loopback-only sealer at `127.0.0.1:8545`, pair `0x272a3ed4b91112005ade5b4161af1adc856ab3f4` |
| wLXON/LXON peg reserves | same call against pair `0x8e90675e054826f61745c0016b895cdc4f220ebc` |
| ETH/USD | `https://api.coingecko.com/api/v3/simple/price` |
| output | atomic write (`tmp` + `os.replace`) to `/var/lib/docker/volumes/lxon-evm_caddy-data/_data/swap/price.json` |

On any upstream failure it exits non-zero and leaves the previous `price.json` in place, so the feed
goes stale rather than wrong. Scheduled every 5 minutes by root's crontab; measured live 2026-11-01,
last write 74 s before the check.

## Who reads it

`lxon-web-ui/landing-light.html` (the USD rows), `lxon-web-ui/app-web.html` (the price card, including
the wLXON figure at `:637` and `:653`), `lxon-web-ui/swap.html`, and `tools/metamask-add-wlxon.html`.
The pages fetch `price.json` relative first, then `/swap/price.json`, because the feed is only
same-origin-readable on the two hosts that serve it.

## Two defects recorded, deliberately left unfixed here

Both are product decisions for the owner, not mechanical bugs, so this commit only moves the file under
version control.

1. **The published wLXON price is derived from the peg pool's ratio, which the payload's own note
   contradicts.** `peg = w1 / w0` (line 51) feeds `priceWlxonInUsd = price_eth * peg * usd` (line 70),
   while lines 71-73 assert wLXON is escrow-backed 1:1 by LXON. Measured 2026-11-01: peg **1.2097**
   LXON/wLXON, so the feed prints wLXON at **$0.273588** against LXON at **$0.226168** — a 21% premium
   that the wrapper does not honour. (Pool reserves then were 18,186.78 wLXON / 22,000 LXON; wrapper
   `totalSupply()` 49,293.389106. The same ratio makes ~187 LXON of open arbitrage available to the
   first caller, which would also self-correct the figure.)
2. **The direction of that ratio rests on a comment.** Line 18 states `token0=wLXON, token1=LXON` and
   nothing verifies it — there is no `symbol()` or `token0()` read in the script. If the ordering were
   wrong the price would silently come out as `1/peg`. This is not theoretical: the sibling pair's
   `token1()` was measured refusing to answer while `token0()` worked.

A third gap is procedural rather than in the code: nothing here has a test. A check worth adding once
the owner rules on (1) is one that fails when `abs(peg - 1.0)` exceeds a stated tolerance, so a drift in
the pool ratio becomes a loud failure instead of a published number.
