#!/bin/bash

# Simple deployment script using curl directly
# This bypasses Hardhat/undici timeout issues

set -e

CHAIN_ID=724
RPC_URL="http://13.61.177.64:8546"
PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY}"

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: DEPLOYER_PRIVATE_KEY environment variable not set"
    exit 1
fi

echo "🏗️  Deploying L3 Mint Contracts to Chain ID $CHAIN_ID"
echo "🌐 RPC URL: $RPC_URL"
echo "🔑 Deployer private key set"

# Check network
echo "🔍 Checking network..."
CHAIN_ID_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$RPC_URL" | jq -r '.result')

CHAIN_ID_DECIMAL=$((16#${CHAIN_ID_HEX#0x}))
echo "✅ Chain ID: $CHAIN_ID_DECIMAL"

if [ "$CHAIN_ID_DECIMAL" -ne "$CHAIN_ID" ]; then
    echo "Error: Chain ID mismatch. Expected $CHAIN_ID, got $CHAIN_ID_DECIMAL"
    exit 1
fi

# Get nonce
echo "🔍 Getting nonce..."
DEPLOYER_ADDRESS=$(echo "0x${PRIVATE_KEY:2:40}")
NONCE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$DEPLOYER_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | jq -r '.result')

echo "✅ Nonce: $NONCE"

# For dry-run, just simulate
if [ "$DRY_RUN" = "true" ]; then
    echo "⚠️  DRY RUN MODE - No actual deployment will be performed"
    echo "📊 Simulated deployment:"
    echo "   ✅ L3MintToken: 0xSIMULATED_L3MINTTOKEN_ADDRESS"
    echo "   ✅ L3ChipManager: 0xSIMULATED_L3CHIPMANAGER_ADDRESS"
    echo "   ✅ L3Redemption: 0xSIMULATED_L3REDEMPTION_ADDRESS"
    exit 0
fi

# For actual deployment, we would need to:
# 1. Compile contracts and get bytecode
# 2. Sign transaction
# 3. Send raw transaction
# This requires additional tools (cast, web3, etc.)

echo "❌ Actual deployment requires Foundry/cast or web3.py"
echo "💡 Use cast for deployment:"
echo "   cast send --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --chain-id $CHAIN_ID <contract-bytecode>"
exit 1