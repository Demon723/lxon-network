# LXON Faucet Discovery - Testnet Only

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x86a7da576852126c8421f7a25f8de7cedf9553c4` - WETH
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
**Date:** October 7, 2026
**Finding:** Faucet exists but is for testnet/devnet only

---

## 📊 Faucet Application Found

**Location:** `/Users/adikamble/LXON/LXON/apps/faucet/`

**Components:**
- Frontend: `index.html`
- Backend: `src/server.ts`
- Port: 3003 (default)

---

## ⚠️ Critical Finding: Testnet Only

**From the faucet HTML:**
```
Devnet tokens are free and replenished daily.
Tokens are for testing only and hold no value.
```

**Configuration:**
- Network: Devnet (Chain ID 724) and Local (Chain ID 31337)
- RPC URL: http://localhost:8545 (default - local)
- Token Contract: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707

**Important:** This is NOT the mainnet token contract.

---

## 🔍 Faucet Details

### Token Specs (from faucet):
- Max Supply: 1,000,000,000
- Emission: 5,000 XON/day, declining 100 XON/day over 10 years
- Transfer Fee: 1% (burned)
- Decimals: 18

### Current Configuration:
```javascript
CONTRACTS = {
  LXON_TOKEN: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707', // Testnet contract
  RPC_URL: 'http://localhost:8545', // Local RPC
  CHAIN_ID: 31337 // Local chain
}
```

### Server Behavior:
- **Faucet request:** Simulated (returns fake transaction hash)
- **Mint:** Simulated (returns fake transaction hash)
- **No actual token transfers**

---

## 🚨 Why This Won't Help

### 1. Wrong Token Contract
- Faucet uses: `0x5FC8d32690cc91D4c39d9d3abcBD16989F875707`
- Mainnet WETH: `0x86a7da576852126c8421F7a25F8dE7cEDF9553C4`
- Mainnet LXON: `0xc0177883C0c662870855660495C697385FE040f5`

**These are different contracts.**

### 2. Wrong Network
- Faucet configured for: Local/Devnet
- You need: Mainnet (Chain ID 724 with https://rpc.lxon.in)

### 3. Simulated Responses
- Faucet server doesn't actually send tokens
- It returns fake transaction hashes
- This is for development/testing only

### 4. Testnet Tokens Only
- HTML explicitly states: "Tokens are for testing only and hold no value"
- Even if it worked, you'd get testnet tokens, not real ones

---

## 🎯 What This Means

**The faucet is for:**
- Development and testing
- Local development environment
- Devnet testing
- Not for mainnet usage

**The faucet is NOT for:**
- Mainnet token distribution
- Real token acquisition
- Production usage
- Your mainnet wallet

---

## 💡 How to Get Real Tokens

### Option 1: Contact LXON Team

**Ask them:**
1. How do I get mainnet LXON tokens?
2. Is there a mainnet distribution?
3. Can you mint tokens to my wallet?
4. What is the token distribution plan?

**Use:** CONTACT_LXON_TEAM_TEMPLATE.md

---

### Option 2: Check for Mainnet Faucet

**Look for:**
- Mainnet faucet URL
- Mainnet token distribution
- Airdrop announcements
- Community giveaways

**Search:**
- LXON website
- LXON Discord
- LXON Telegram
- LXON Twitter

---

### Option 3: Acquire Native LXON

**To get WETH, you need:**
1. Native LXON (network gas token)
2. Wrap it into WETH

**How to get native LXON:**
- Buy from someone
- Mine/validate
- Receive as payment
- Team distribution

---

### Option 4: Wait for Distribution

**LXON team might:**
- Airdrop tokens to community
- Distribute to early adopters
- Launch with token sale
- Provide faucet for mainnet

**Monitor:**
- LXON announcements
- Community channels
- Official website

---

## 📋 Summary

**Faucet Status:**
- ✅ Exists in codebase
- ❌ Testnet/devnet only
- ❌ Simulated (doesn't actually send tokens)
- ❌ Wrong token contract
- ❌ Wrong network configuration

**Your Situation:**
- You have 0 tokens on mainnet
- Faucet won't help (wrong network)
- Need team assistance or mainnet distribution

**Next Steps:**
1. Contact LXON team about mainnet token distribution
2. Monitor for mainnet faucet or airdrop
3. Research how to acquire native LXON
4. Wait for official token distribution

---

## 📁 Relevant Files

- `/Users/adikamble/LXON/LXON/apps/faucet/index.html` - Faucet frontend
- `/Users/adikamble/LXON/LXON/apps/faucet/src/server.ts` - Faucet backend
- `NO_TOKENS_MINTED_STATUS.md` - Current token status
- `CONTACT_LXON_TEAM_TEMPLATE.md` - Team contact template

---

**Bottom line: The faucet exists but is for testnet only. You need to contact the LXON team or wait for mainnet token distribution.**
