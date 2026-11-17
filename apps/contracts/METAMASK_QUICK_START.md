# Quick Start: Add LXON Network and Tokens to MetaMask

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x14711906a15be7cd861f0378d26b65d37bc5a9df` - USDC
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## 🦊 Step 1: Add LXON Network to MetaMask

1. Open MetaMask
2. Click the network dropdown (top left)
3. Click "Add Network" or "Custom RPC"
4. Fill in these details:

**Network Name:** LXON
**New RPC URL:** https://rpc.lxon.in
**Chain ID:** 724
**Currency Symbol:** LXON
**Block Explorer URL:** (leave blank for now)

5. Click "Save"
6. You'll be switched to LXON network automatically

---

## 💰 Step 2: Import LXON Token

1. Make sure you're on LXON network
2. Scroll to the bottom of your asset list
3. Click "Import Tokens"
4. Click "Custom Token"
5. Enter:

**Token Contract Address:** `0xc0177883C0c662870855660495C697385FE040f5`
**Token Symbol:** LXON
**Decimals of Precision:** 6

6. Click "Add Custom Token"
7. Click "Import"

---

## 💵 Step 3: Import USDC Token

1. Scroll to the bottom → "Import Tokens"
2. Click "Custom Token"
3. Enter:

**Token Contract Address:** `0x14711906a15BE7Cd861f0378D26b65D37bC5a9df`
**Token Symbol:** USDC
**Decimals of Precision:** 18

4. Click "Add Custom Token"
5. Click "Import"

---

## 🔷 Step 4: Import WETH Token (Optional)

1. Scroll to the bottom → "Import Tokens"
2. Click "Custom Token"
3. Enter:

**Token Contract Address:** `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c`
**Token Symbol:** WETH
**Decimals of Precision:** 18

4. Click "Add Custom Token"
5. Click "Import"

---

## ✅ Done!

Now you can:
- See your LXON balance (should show 2B LXON)
- See your USDC balance
- Use the DEX to trade LXON ↔ USDC at $2/LXON
- Access DeFi features

---

## 📱 Trading

**To trade:**
1. Open the trading interface: http://localhost:8081/trading-interface-enhanced.html
2. Click "Connect Wallet"
3. Approve network switch if prompted
4. Select tokens and amounts
5. Click "Swap"

---

## ❓ Troubleshooting

**"Network not found" error:**
- Make sure you added the LXON network correctly
- Check that RPC URL is: https://rpc.lxon.in
- Check that Chain ID is: 724

**"Token not found" error:**
- Make sure you're on LXON network
- Double-check the contract address
- Make sure decimals are correct

**"Wrong network" error:**
- Switch to LXON network in MetaMask
- Refresh the trading interface

---

## 🎯 Your Wallet Address

Your wallet address is displayed in MetaMask (click "Account 1" to copy).

**Your current balance should show:**
- Native LXON: ~10 LXON (for gas)
- LXON Token: 2,000,000,000 LXON
- USDC: 0 (initially)
- WETH: 0 (initially)

---

*Last Updated: 2026-10-06*
