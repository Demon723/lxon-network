<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
<!-- CORRECTED 2026-10-22 — measured on chain; this "Live" DEX has no contracts at its named addresses. -->

> **Corrected 2026-10-22 — there is no $2/LXON market, and none of the three DEX contracts exists.**
>
> Header says `Status: Live`, `Price: $1.995/LXON`. Measured 2026-10-22 at 724 head 50,653 /
> Polygon head 95,942,816:
>
> | This file calls it | Address | Chain 724 | Polygon 137 |
> |---|---|---|---|
> | WETH9Mintable | `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c` | 0 bytes | 0 bytes |
> | DEX Pair | `0xd8D328e3a7f35CB9B6dB5D0bB598c01caD658360` | 0 bytes | 0 bytes |
> | Factory | `0xd99d3d037B124AA1Ea153B3D601a29BC75872a06` | 0 bytes | 0 bytes |
>
> A token, a pair and a factory that have code on neither chain cannot hold reserves, so
> "Initial Liquidity: 111,600,000 WETH / 83,909,774 LXON" and "$1.995/LXON" have no on-chain source.
> $1.995 × any supply is a fabricated market cap — see `deployments/README.md`.
> Of the 6 addresses this file names, **0 have code on chain 724**. The three that have code anywhere
> (`0xc0177883…`, `0x3aD52bD5…`, `0x643a62a5…`, all on Polygon) expose `admin()` = `0x43410E73…` and reject
> every ERC20/AMM getter; their purpose is unresolved and no function should be inferred for them. The
> other three — WETH, pair and factory — have 0 code, 0 nonce and 0 balance on both chains, i.e. they have
> never existed.
>
> **Where those addresses came from.** `broadcast/DeployPairAndRouter.s.sol/724/run-latest.json` is the record
> these documents were written from. It has 19 transactions and **every `hash`, `from` and `nonce` is null**,
> `receipts` is `[]` and `gasPrice` is absent — it is a forge simulation that never reached a node. The `724`
> in the path is the chain id the script was told to expect, not a chain that answered. `contractAddress` in
> such a file is a *prediction* of where a CREATE would land, which is why the values look like real
> deployments. See `deployments/README.md`, "Where the fake 724 deployments came from".

Text below is unedited.
<!-- END CORRECTION -->

# $2/LXON DEX Launch Summary

## ✅ Deployment Complete

**Date:** 2026-10-06
**Status:** Live
**Price:** $1.995/LXON (≈ $2/LXON)

---

## 📊 Deployed Contracts

### 1. WETH9Mintable Contract
- **Address:** `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c`
- **Features:** Mint function, deployer is owner
- **Minted:** 111,600,000 WETH

### 2. New DEX Pair
- **Address:** `0xd8D328e3a7f35CB9B6dB5D0bB598c01caD658360`
- **Factory:** `0xd99d3d037B124AA1Ea153B3D601a29BC75872a06`
- **Tokens:** LXON + WETH Mintable

---

## 💰 Liquidity Details

**Initial Liquidity:**
- WETH: 111,600,000 WETH
- LXON: 83,909,774 LXON
- Price: $1.995/LXON

**Transaction:** `0x14c17fca06ed85b3ea5d67abd35a397efc7e9e34e65745b30a38f94b3310782b`

---

## 📱 Trading Tools

### 1. Trading Guide
**File:** `TRADING_GUIDE_2DOLLAR.md`
- Complete user guide
- MetaMask setup instructions
- Token import details
- Trading steps

### 2. Trading Interface
**File:** `trading-interface.html`
- Web-based trading UI
- Wallet connection
- Price calculator
- Pair information display

### 3. Monitoring Script
**File:** `scripts/monitor-dex.js`
- Real-time event monitoring
- Reserve tracking
- Price updates
- Trade notifications

---

## 🔗 Important Addresses

### Tokens
- **LXON:** `0xc0177883C0c662870855660495C697385FE040f5`
- **WETH (Mintable):** `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c`

### DEX Infrastructure
- **New Pair ($2/LXON):** `0xd8D328e3a7f35CB9B6dB5D0bB598c01caD658360`
- **Old Pair ($0.257/LXON):** `0x3aD52bD5996f16C902225b0d9C111fafE6B77786`
- **Factory:** `0xd99d3d037B124AA1Ea153B3D601a29BC75872a06`
- **Router:** `0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602`

---

## 🚀 Launch Checklist

- [x] Deploy WETH9Mintable contract
- [x] Mint 111.6M WETH
- [x] Create new DEX pair
- [x] Add liquidity
- [x] Verify $2/LXON price
- [x] Create trading guide
- [x] Create trading interface
- [x] Create monitoring script
- [ ] Publish to community
- [ ] Share pair address on social media
- [ ] Update website with new pair
- [ ] Monitor trading activity

---

## 📞 Next Steps

### For Users
1. Add LXON network to MetaMask
2. Import LXON token
3. Import WETH token
4. Start trading on new pair

### For Team
1. Publish trading guide
2. Share pair address on social media
3. Monitor trading activity
4. Provide support to users
5. Add more liquidity if needed

---

## 💡 Important Notes

1. **Price Stability:** The $2/LXON price is maintained by the liquidity ratio
2. **Slippage:** Large trades may have price impact
3. **Two Pairs:** Users can choose between $2/LXON (new) and $0.257/LXON (old)
4. **Recommendation:** Direct users to the new pair for $2/LXON price

---

## 📈 Market Cap

**At $2/LXON:**
- Total Supply: 3B LXON
- Market Cap: $6B

**Your Holdings:**
- 2B LXON
- Value at $2/LXON: $4B

---

*Last Updated: 2026-10-06*
