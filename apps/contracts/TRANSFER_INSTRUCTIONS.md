# Instructions: Transfer Founder WETH to Your Wallet

## Prerequisites

1. **Founder's Private Key** - You need the private key for address `0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3`

2. **Your Wallet Address** - The address where you want to receive the WETH

## Step 1: Add Founder Private Key to .env

Open `/Users/adikamble/LXON/LXON/apps/contracts/.env` and add:

```env
FOUNDER_PRIVATE_KEY=0xYOUR_FOUNDER_PRIVATE_KEY_HERE
YOUR_WALLET_ADDRESS=0xYOUR_WALLET_ADDRESS_HERE
```

**Important:**
- Keep the private key secure
- Never commit .env to git
- This key controls the founder's entire wallet

## Step 2: Run the Transfer Script

```bash
cd /Users/adikamble/LXON/LXON/apps/contracts
npx hardhat run scripts/transfer-founder-weth.ts --network lxonMainnet
```

The script will:
1. Verify the private key matches the founder address
2. Show the WETH balance (~2,326 WETH = ~$3,489)
3. Wait 5 seconds for confirmation
4. Transfer ALL WETH to your wallet address
5. Confirm the transfer

## Step 3: After Transfer

Once you have the WETH in your wallet:

### Option A: If You Can Bridge to Ethereum

1. Use a bridge service (LayerZero, Wormhole, etc.)
2. Bridge WETH from LXON to Ethereum Mainnet
3. Send WETH to CEX deposit address
4. Convert to USDC
5. Withdraw to bank

### Option B: If No Bridge Available

1. Contact LXON team about bridge infrastructure
2. Or use the LXONBridge contract if operational
3. Or wait for bridge support

### Option C: Use Your Wallet Address as CEX Deposit

Some CEXs might accept deposits directly on LXON if they support the network.

## Alternative: Manual Transfer in MetaMask

If you don't want to use the script:

1. Open MetaMask
2. Add LXON network to MetaMask:
   - Network Name: LXON Mainnet
   - RPC URL: http://16.171.20.249:8546
   - Chain ID: 724
   - Currency Symbol: LXON
3. Import founder's wallet using private key
4. Switch to LXON network
5. Send WETH to your address
6. Import your wallet in MetaMask
7. Verify receipt

## Security Warning

⚠️ **Important Security Notes:**

- Never share private keys with anyone
- After using the founder's private key, consider rotating it
- The founder should transfer funds to a new secure wallet
- Store private keys in hardware wallets for long-term security

## Next Steps After WETH Transfer

Once you have WETH in your wallet:

1. **Research bridge options** for LXON → Ethereum
2. **Check if CEX supports LXON network** for direct deposit
3. **Contact LXON team** about bridge infrastructure
4. **Use OTC desk** if you have large amounts

---

**Current Founder WETH:**
- Balance: 2,326.24 WETH
- Value: ~$3,489 USD
- Contract: 0x007696cdF0Bf860823126D72C8e3D52448B5285E

**Ready to transfer when you have the private key.**
