#!/bin/bash

# Peer Bridge Deployment Script
# Deploys LxonBridgeMultiSig on Ethereum Mainnet, Sepolia, and Holesky

set -e

echo "=========================================="
echo "LXON Peer Bridge Deployment"
echo "=========================================="
echo ""

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo "❌ Error: forge is not installed"
    echo "Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "Please create .env file with the following variables:"
    echo "  MAINNET_RPC_URL"
    echo "  SEPOLIA_RPC_URL"
    echo "  HOLESKY_RPC_URL"
    echo "  DEPLOYER_PRIVATE_KEY"
    exit 1
fi

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Check required environment variables
if [ -z "$MAINNET_RPC_URL" ] || [ -z "$SEPOLIA_RPC_URL" ] || [ -z "$HOLESKY_RPC_URL" ]; then
    echo "❌ Error: Missing RPC URLs in .env file"
    echo "Required: MAINNET_RPC_URL, SEPOLIA_RPC_URL, HOLESKY_RPC_URL"
    exit 1
fi

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "❌ Error: DEPLOYER_PRIVATE_KEY not set in .env file"
    exit 1
fi

echo "✅ Foundry and environment configuration verified"
echo ""

# Deploy on Ethereum Mainnet
echo "=========================================="
echo "Deploying on Ethereum Mainnet"
echo "=========================================="
read -p "Deploy on Ethereum Mainnet? (Requires gas fees) [y/N]: " deploy_mainnet

if [ "$deploy_mainnet" = "y" ] || [ "$deploy_mainnet" = "Y" ]; then
    echo "Deploying..."
    forge script script/DeployLxonBridgeMultiSig_EthereumMainnet.s.sol \
        --rpc-url $MAINNET_RPC_URL \
        --private-key $DEPLOYER_PRIVATE_KEY \
        --broadcast \
        --verify \
        -vv

    echo "✅ Ethereum Mainnet deployment complete"
    echo ""
else
    echo "⏭️  Skipping Ethereum Mainnet deployment"
    echo ""
fi

# Deploy on Sepolia Testnet
echo "=========================================="
echo "Deploying on Sepolia Testnet"
echo "=========================================="
read -p "Deploy on Sepolia Testnet? [y/N]: " deploy_sepolia

if [ "$deploy_sepolia" = "y" ] || [ "$deploy_sepolia" = "Y" ]; then
    echo "Deploying..."
    forge script script/DeployLxonBridgeMultiSig_Sepolia.s.sol \
        --rpc-url $SEPOLIA_RPC_URL \
        --private-key $DEPLOYER_PRIVATE_KEY \
        --broadcast \
        --verify \
        -vv

    echo "✅ Sepolia Testnet deployment complete"
    echo ""
else
    echo "⏭️  Skipping Sepolia Testnet deployment"
    echo ""
fi

# Deploy on Holesky Testnet
echo "=========================================="
echo "Deploying on Holesky Testnet"
echo "=========================================="
read -p "Deploy on Holesky Testnet? [y/N]: " deploy_holesky

if [ "$deploy_holesky" = "y" ] || [ "$deploy_holesky" = "Y" ]; then
    echo "Deploying..."
    forge script script/DeployLxonBridgeMultiSig_Holesky.s.sol \
        --rpc-url $HOLESKY_RPC_URL \
        --private-key $DEPLOYER_PRIVATE_KEY \
        --broadcast \
        --verify \
        -vv

    echo "✅ Holesky Testnet deployment complete"
    echo ""
else
    echo "⏭️  Skipping Holesky Testnet deployment"
    echo ""
fi

echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""
echo "Please record the deployed bridge addresses from the output above."
echo "You will need these addresses to configure peer bridges on LXON."
echo ""
echo "Next steps:"
echo "1. Record the deployed bridge addresses"
echo "2. Update scripts/setup-peer-bridges.ts with the new addresses"
echo "3. Run: npx hardhat run scripts/setup-peer-bridges.ts --network lxon"
echo ""
