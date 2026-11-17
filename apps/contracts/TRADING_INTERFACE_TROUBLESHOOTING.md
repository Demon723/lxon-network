# Trading Interface Troubleshooting

## 🔍 Common Issues & Solutions

### Issue 1: Page Not Loading
**Solution:**
1. Check if server is running on port 8081
2. Try refreshing the page
3. Clear browser cache
4. Try incognito mode

### Issue 2: Wallet Connection Failed
**Solution:**
1. Ensure MetaMask is installed
2. Ensure LXON network is added to MetaMask
3. Try manually switching to LXON network first
4. Refresh the page

### Issue 3: Network Status Error
**Solution:**
1. Manually switch to LXON network in MetaMask
2. Refresh the page
3. Network status should turn green

### Issue 4: Tokens Not Showing
**Solution:**
1. Import LXON token to MetaMask
2. Import USDC token to MetaMask
3. Refresh the page
4. Tokens should appear in dropdown

### Issue 5: Swap Button Disabled
**Solution:**
1. Connect wallet first
2. Ensure on LXON network
3. Swap button should enable

---

## 🎯 Quick Fix Steps

### Step 1: Verify Server
```bash
# Check if server is running
lsof -i :8081
```

### Step 2: Restart Server
```bash
# Kill existing server
kill 76180

# Start new server
cd /Users/adikamble/LXON/LXON/apps/contracts
python3 -m http.server 8081
```

### Step 3: Open in Browser
1. Open browser
2. Go to: http://localhost:8081/trading-interface-enhanced.html
3. Check if page loads

### Step 4: Check Console
1. Open browser DevTools (F12)
2. Check Console tab for errors
3. Report any errors

---

## ❓ What Error Are You Seeing?

**Please describe:**
- A) Page not loading
- B) Wallet connection failed
- C) Network error message
- D) Tokens not in dropdown
- E) Swap button disabled
- F) Something else

**This will help me fix the specific issue.**
