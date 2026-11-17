# Trading Interface Update - USDC Support

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x14711906a15be7cd861f0378d26b65d37bc5a9df` - USDC
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## ✅ Trading Interface Updated for USDC

**Date:** 2026-10-06
**Status:** Updated and Ready

---

## 🔄 Changes Made

### 1. Token Selection
- **Changed:** WETH → USDC
- **Token In:** LXON or USDC
- **Token Out:** USDC or LXON

### 2. Price Calculation
- **Old:** 1.33 WETH per LXON
- **New:** 2 USDC per LXON ($2/LXON)

### 3. Contract Addresses
- **LXON:** `0xc0177883C0c662870855660495C697385FE040f5` (unchanged)
- **Quote Asset:** `0x14711906a15BE7Cd861f0378D26b65D37bC5a9df` (USDC, was WETH)
- **DEX Pair:** `0x145349bAe112F2b67DDC62f7e9Ba95A0B54656e8` (USDC pair, was WETH pair)

### 4. Display
- **Title:** $2/LXON (USDC)
- **Pair Info:** Shows USDC address and $2/LXON price

---

## 📋 Import Instructions

### Step 1: Import LXON Token (if not already)
1. Open MetaMask (ensure on LXON network)
2. Scroll to bottom → "Import Tokens"
3. Click "Custom Token"
4. Enter:
   - **Token Contract Address:** `0xc0177883C0c662870855660495C697385FE040f5`
   - **Token Symbol:** LXON
   - **Decimals of Precision:** 6
5. Click "Add Custom Token"
6. Click "Import"

### Step 2: Import USDC Token
1. Scroll to bottom → "Import Tokens"
2. Click "Custom Token"
3. Enter:
   - **Token Contract Address:** `0x14711906a15BE7Cd861f0378D26b65D37bC5a9df`
   - **Token Symbol:** USDC
   - **Decimals of Precision:** 18
4. Click "Add Custom Token"
5. Click "Import"

### Step 3: Connect Wallet
1. Open trading interface: http://localhost:8081/trading-interface-enhanced.html
2. Click "Connect Wallet"
3. Approve network switch to LXON
4. Wallet will show: "✅ Connected to LXON network"

### Step 4: Swap
1. Select LXON in "From" dropdown
2. Select USDC in "To" dropdown
3. Enter amount (e.g., 1000 LXON)
4. See output: 2000 USDC
5. Click "Swap"

---

## 💰 Price Calculation

**Example:**
- Input: 1,000 LXON
- Output: 2,000 USDC
- Price: $2/LXON
- USDC is USD-equivalent stablecoin

---

## 🎯 Benefits

1. **Real USD Value:** USDC is pegged to USD
2. **Better UX:** Users see "USDC" instead of "WETH"
3. **Direct Conversion:** LXON → USDC = LXON → USD
4. **Standard Practice:** Most DEXs use stablecoins

---

## 📊 Updated Files

- `trading-interface-enhanced.html` - Updated with USDC support
- Token dropdowns now show USDC
- Price calculator uses $2/LXON
- Pair info shows USDC address

---

## ✅ Ready to Use

**Updated Interface:** http://localhost:8081/trading-interface-enhanced.html

**After importing tokens:**
1. Connect wallet
2. Select LXON → USDC
3. Enter amount
4. Swap at $2/LXON
5. Get USDC (USD-equivalent)

---

*Last Updated: 2026-10-06*
