# How to Add LXON Network to MetaMask

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## 📋 Network Details

**LXON Network Configuration:**
- **Network Name:** LXON
- **RPC URL:** https://rpc.lxon.in
- **Chain ID:** 724
- **Currency Symbol:** LXON
- **Block Explorer:** (Leave blank or use https://explorer.lxon.in if available)

---

## 🦊 Method 1: Manual Addition (Recommended)

### Step-by-Step Instructions

1. **Open MetaMask**
   - Click the MetaMask extension icon in your browser

2. **Click Network Dropdown**
   - Look at the top left of MetaMask
   - Click where it says "Ethereum Mainnet" or another network
   - A dropdown menu will appear

3. **Click "Add Network"**
   - At the bottom of the dropdown, click "Add Network" or "Custom RPC"

4. **Fill in Network Details**
   - **Network Name:** LXON
   - **New RPC URL:** https://rpc.lxon.in
   - **Chain ID:** 724
   - **Currency Symbol:** LXON
   - **Block Explorer URL:** (Leave blank for now)

5. **Click "Save"**
   - MetaMask will add the network
   - You'll be switched to the LXON network automatically

6. **Verify**
   - You should see "LXON" in the network dropdown
   - Your account address should be the same
   - You may see 0 LXON balance (native currency)

---

## 🔗 Method 2: Deep Link (Automatic)

**Click this link to auto-add LXON network:**
```
https://metamask.app.link/draft/https://rpc.lxon.in/724
```

**Or use this Chainlist link (if available):**
```
https://chainlist.org/chain/724
```

---

## 🌐 Method 3: Via Trading Interface

1. Open trading interface: http://localhost:8080/trading-interface-enhanced.html
2. Click "Connect Wallet"
3. MetaMask will prompt to add LXON network
4. Approve the network addition
5. Switch to LXON network

---

## 📱 Method 4: Mobile MetaMask

1. Open MetaMask mobile app
2. Tap the network name at the top
3. Tap "Add Network"
4. Select "Custom Network"
5. Enter:
   - **Network Name:** LXON
   - **RPC URL:** https://rpc.lxon.in
   - **Chain ID:** 724
   - **Symbol:** LXON
6. Tap "Add"
7. Switch to LXON network

---

## 🔍 Verify Network Addition

After adding, check:
1. Network dropdown shows "LXON"
2. Chain ID is 724
3. RPC URL is https://rpc.lxon.in
4. Currency symbol is LXON
5. You can see your account address

---

## ⚠️ Troubleshooting

### Issue: "Invalid Chain ID"
**Solution:**
- Ensure Chain ID is 724 (decimal)
- Do NOT use 0x2d4 (hexadecimal)
- MetaMask expects decimal format

### Issue: "RPC URL Not Working"
**Solution:**
- Use https://rpc.lxon.in
- Do NOT use the IP address (SSL error)
- Ensure https:// is included

### Issue: "Network Already Exists"
**Solution:**
- Switch to the existing LXON network
- Or delete and re-add if needed

### Issue: "Cannot Connect"
**Solution:**
- Check your internet connection
- Verify RPC URL is correct
- Try refreshing MetaMask
- Restart your browser

---

## 📊 After Adding Network

Once LXON network is added:
1. You'll see "LXON" in network dropdown
2. Your account will work on LXON network
3. You can add LXON and WETH tokens
4. You can use the trading interface
5. You can swap tokens

---

## 🎯 Next Steps (After Network is Added)

1. **Import LXON Token**
   - Contract: 0xc0177883C0c662870855660495C697385FE040f5
   - Symbol: LXON
   - Decimals: 6

2. **Import WETH Token**
   - Contract: 0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c
   - Symbol: WETH
   - Decimals: 18

3. **Start Trading**
   - Open trading interface
   - Connect wallet
   - Start swapping

---

## ✅ Quick Reference Card

```
Network Name: LXON
RPC URL: https://rpc.lxon.in
Chain ID: 724
Currency Symbol: LXON
Block Explorer: (blank)
```

---

*Last Updated: 2026-10-06*
