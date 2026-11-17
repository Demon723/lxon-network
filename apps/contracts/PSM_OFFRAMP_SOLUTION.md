# LXON Redemption System - PSM Off-Ramp Solution

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x14711906a15be7cd861f0378d26b65d37bc5a9df` - USDC
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## ✅ Deployment Summary

**Date:** 2026-10-06
**Status:** LXON Side Deployed, Ethereum Side Pending

---

## 📊 What Was Deployed

### LxonRedemption Contract
- **Address:** `0xf66C6b45F1dE236Df7C6587bd8771f0C8B55941C`
- **Network:** LXON (Chain ID 724)
- **LXON Token:** `0xc0177883C0c662870855660495C697385FE040f5`
- **USDC Token:** `0x14711906a15BE7Cd861f0378D26b65D37bC5a9df`
- **PSM Address:** `0x0000000000000000000000000000000000000000` (placeholder)
- **Custodian Wallet:** Deployer address (to be updated)
- **Owner:** Deployer
- **Redemption Fee:** 0.10% (10 basis points)

---

## 🔧 How the PSM Off-Ramp Works

### The Peg Stability Module (PSM) Approach

This is the same proven model used by MakerDAO:

1. **PSM holds USDC reserves** on Ethereum
2. **LXON is pegged to USDC** (1 LXON = $2 USDC)
3. **Users redeem LXON → USDC** via PSM
4. **USDC can be converted to USD** via custodian or CEX
5. **Custodian wires USD to bank account**

### Flow Diagram
```
User has LXON on LXON
         ↓
Redeem via LxonRedemption contract
         ↓
PSM burns LXON, sends USDC to user
         ↓
User has USDC on Ethereum
         ↓
Convert to USD via custodian/CEX
         ↓
USD wired to bank account
```

---

## ⚠️ What's Still Needed

### 1. Deploy PSM on Ethereum
- **Status:** ❌ Not deployed
- **Cost:** ~0.05 ETH
- **Function:** Holds USDC reserves, handles LXON redemption
- **Timeline:** 1-2 hours (after funding)

### 2. Fund PSM with USDC
- **Status:** ❌ Not funded
- **Amount:** Depends on expected redemption volume
- **Minimum:** $10,000 USDC recommended
- **Source:** Purchase real USDC on Ethereum

### 3. Sign Up with Custodian
- **Status:** ❌ Not signed up
- **Options:** Fireblocks, BitGo, licensed OTC desk
- **Function:** Converts USDC to USD, wires to bank
- **Cost:** 0.1-0.5% per transaction
- **Timeline:** 1-2 weeks (KYC/AML)

### 4. Deploy Backend Server
- **Status:** ❌ Not deployed
- **File:** `lxon-offramp.js` (from DeepSeek files)
- **Function:** Integrates with custodian API
- **Hosting:** $50-100/month
- **Timeline:** 1-2 days

### 5. Deploy Frontend UI
- **Status:** ❌ Not deployed
- **File:** `RedeemLxon.jsx` (from DeepSeek files)
- **Function:** User interface for redemption
- **Hosting:** Free (Vercel/Netlify)
- **Timeline:** 1 day

---

## 💰 Cost Breakdown

### One-Time Costs
- PSM deployment on Ethereum: ~0.05 ETH (~$150-200)
- Backend server setup: $0-100
- Frontend deployment: $0

### Ongoing Costs
- Backend server hosting: $50-100/month
- Custodian fees: 0.1-0.5% per transaction
- USDC reserves: $10,000+ (held in PSM)

### Total Initial Investment
- **Minimum:** ~$150-200 (PSM deployment only)
- **Recommended:** ~$10,200 (PSM + USDC reserves)
- **Full System:** ~$10,300 (PSM + reserves + server)

---

## 🎯 Why This is Better Than Circle USDC

| Feature | Circle USDC on LXON | PSM Off-Ramp |
|---------|---------------------|--------------|
| Requires Circle approval | ✅ Yes | ❌ No |
| Timeline | 1-3 months | 2-4 weeks |
| Cost | Free | $150-200 + reserves |
| Real USD access | ✅ Yes | ✅ Yes |
| Bank withdrawal | ✅ Yes | ✅ Yes |
| Success rate | Low (new chains) | High (proven model) |
| Control | Circle controls | You control |

---

## 📋 Implementation Roadmap

### Phase 1: Ethereum Side (Need 0.05 ETH)
1. Fund deployer wallet with 0.05 ETH
2. Deploy PSM contract on Ethereum
3. Purchase USDC reserves (recommended $10,000+)
4. Fund PSM with USDC
5. Update PSM address in LXON redemption contract

### Phase 2: Custodian Integration
1. Sign up with Fireblocks or BitGo
2. Complete KYC/AML verification
3. Get API credentials
4. Configure custodian wallet address
5. Test integration

### Phase 3: Backend Deployment
1. Deploy `lxon-offramp.js` to server
2. Configure with custodian API
3. Set up database
4. Test redemption flow

### Phase 4: Frontend Deployment
1. Deploy `RedeemLxon.jsx` to Vercel/Netlify
2. Connect to backend API
3. Add to trading interface
4. Test end-to-end flow

### Phase 5: Launch
1. Announce redemption feature
2. Monitor transactions
3. Adjust fees if needed
4. Scale infrastructure

---

## 🚀 Current Status

**Completed:**
- ✅ LxonRedemption contract deployed on LXON
- ✅ LXON token configured
- ✅ USDC token configured
- ✅ Custodian wallet placeholder set
- ✅ Redemption fee set to 0.10%

**Pending:**
- ❌ PSM deployment on Ethereum (need 0.05 ETH)
- ❌ USDC reserves funding
- ❌ Custodian signup
- ❌ Backend server deployment
- ❌ Frontend UI deployment

---

## 💡 Alternative: Use Custom USDC Only

**If you don't want to deploy PSM:**

Users can:
- Trade LXON ↔ custom USDC on DEX at $2/LXON
- Use custom USDC within LXON ecosystem
- Cannot convert to real USD
- Cannot withdraw to bank

**Pros:**
- No additional cost
- Works now
- No external dependencies

**Cons:**
- Not real USD
- Cannot withdraw to bank
- Limited to LXON ecosystem

---

## ❓ Next Steps

### Option A: Deploy PSM (Recommended for Real USD)
- Fund wallet with 0.05 ETH
- Deploy PSM on Ethereum
- Purchase USDC reserves
- Complete full system

### Option B: Use Custom USDC (Current Solution)
- Skip PSM deployment
- Use custom USDC for trading
- Works within LXON only

### Option C: Contact LXON Team
- Ask them to deploy PSM
- Ask them to fund USDC reserves
- Get official support

---

## 📞 Custodian Options

### Fireblocks
- **Website:** https://fireblocks.com
- **Features:** Off-ramp, custody, API
- **Fees:** 0.1-0.5%
- **Timeline:** 1-2 weeks

### BitGo
- **Website:** https://bitgo.com
- **Features:** Off-ramp, custody, API
- **Fees:** 0.1-0.5%
- **Timeline:** 1-2 weeks

### OTC Desks
- **Genesis Trading:** https://genesis.com
- **Circle Trade:** https://circle.com
- **Features:** Large transactions
- **Minimum:** Usually $10,000+

---

## ✅ Summary

**LXON Redemption contract is deployed and ready.**

**To enable real USD withdrawals:**
1. Deploy PSM on Ethereum (need 0.05 ETH)
2. Fund with USDC reserves
3. Sign up with custodian
4. Deploy backend and frontend

**Timeline:** 2-4 weeks after funding

**Cost:** ~$150-200 initial + USDC reserves

**This is a proven, legitimate way to get real USD from LXON without needing Circle's approval.**

---

*Last Updated: 2026-10-06*
