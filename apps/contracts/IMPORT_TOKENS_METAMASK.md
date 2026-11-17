# How to Import LXON Token to MetaMask

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## 📋 Token Information

**LXON Token Details:**
- **Contract Address:** `0xc0177883C0c662870855660495C697385FE040f5`
- **Symbol:** LXON
- **Decimals:** 6
- **Network:** LXON (Chain ID: 724)

---

## 🦊 Method 1: Manual Import

### Step 1: Ensure LXON Network is Added
1. Open MetaMask
2. Click network dropdown (top left)
3. Select "LXON" network
4. If not added, add it first:
   - Network Name: LXON
   - RPC URL: https://rpc.lxon.in
   - Chain ID: 724
   - Currency Symbol: LXON

### Step 2: Import LXON Token
1. Make sure you're on LXON network
2. Scroll down to bottom of asset list
3. Click "Import Tokens"
4. Click "Custom Token"
5. Enter:
   - **Token Contract Address:** `0xc0177883C0c662870855660495C697385FE040f5`
   - **Token Symbol:** LXON
   - **Decimals of Precision:** 6
6. Click "Add Custom Token"
7. Click "Import"

---

## 🔗 Method 2: Direct Import Link

**Click this link to auto-import:**
```
https://metamask.app.link/draft/a0xEAC4179B1737aCA8144C973CeD3B758e9B7dF89c0177883C0c662870855660495C697385FE040f5
```

**Or use this format:**
```
https://metamask.app.link/draft/https://rpc.lxon.in/724/0xc0177883C0c662870855660495C697385FE040f5
```

---

## 🌐 Method 3: Via Block Explorer

1. Go to block explorer (if available)
2. Search for LXON token address: `0xc0177883C0c662870855660495C697385FE040f5`
3. Click on the token
4. Look for "Add to MetaMask" button
5. Click and approve

---

## 💼 Method 4: Via Trading Interface

1. Open trading interface: http://localhost:8080/trading-interface-enhanced.html
2. Click "Connect Wallet"
3. The interface may prompt to add LXON token
4. Approve the token import

---

## 🔍 Verify Token Import

After importing, check:
1. LXON should appear in your asset list
2. Your balance should show (if you have LXON)
3. Symbol should be "LXON"
4. Decimals should be 6

---

## ⚠️ Troubleshooting

### Issue: "Token Not Found"
**Solution:**
- Verify contract address is correct: `0xc0177883C0c662870855660495C697385FE040f5`
- Ensure you're on LXON network (Chain ID: 724)
- Check if token contract exists on LXON network

### Issue: "Zero Balance"
**Solution:**
- Your wallet may not have LXON
- Check the correct wallet address
- The token balance might be in a different wallet

### Issue: "Wrong Decimals"
**Solution:**
- Ensure decimals is set to 6
- Do not use 18 (that's for WETH)

---

## 📱 Import WETH Token (Also Needed)

**WETH Token Details:**
- **Contract Address:** `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c`
- **Symbol:** WETH
- **Decimals:** 18

**Import WETH:**
1. Click "Import Tokens"
2. Click "Custom Token"
3. Enter:
   - **Token Contract Address:** `0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c`
   - **Token Symbol:** WETH
   - **Decimals of Precision:** 18
4. Click "Add Custom Token"
5. Click "Import"

---

## ✅ Complete Setup Checklist

- [ ] LXON network added to MetaMask
- [ ] LXON token imported
- [ ] WETH token imported
- [ ] Wallet connected to LXON network
- [ ] Token balances visible
- [ ] Ready to swap

---

## 🎯 After Import

Once both tokens are imported:
1. Open trading interface
2. Connect wallet
3. You should see LXON and WETH in the dropdown
4. Select tokens and start swapping

---

*Last Updated: 2026-10-06*
