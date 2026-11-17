#!/bin/bash

# Blockchain Node Installation Script for AWS EC2
# This script installs and configures the LXON blockchain node

set -e

SSH_KEY="~/.ssh/lxon-blockchain-key-v3.pem"
SSH_USER="ubuntu"
CHAIN_ID=724
NETWORK_NAME="lxon"

# Instances to install blockchain node on
INSTANCES=(
    "13.61.177.64:validator-1:8546"
    "16.171.173.70:validator-2:8547"
)

echo "🚀 Blockchain Node Installation for Chain ID $CHAIN_ID"
echo "======================================================"
echo ""

for instance in "${INSTANCES[@]}"; do
    IFS=':' read -r IP NAME PORT <<< "$instance"
    
    echo "📦 Installing blockchain node on $NAME ($IP)..."
    
    # Test SSH connection
    echo "   Testing SSH connection..."
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$IP "echo 'SSH successful'" > /dev/null 2>&1; then
        echo "   ✅ SSH connection successful"
    else
        echo "   ❌ SSH connection failed"
        continue
    fi
    
    # Update system
    echo "   Updating system packages..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get update && sudo apt-get upgrade -y"
    
    # Install dependencies
    echo "   Installing dependencies..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get install -y docker.io docker-compose git curl wget"
    
    # Start Docker
    echo "   Starting Docker..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo systemctl start docker && sudo systemctl enable docker"
    
    # Create blockchain directory
    echo "   Creating blockchain directory..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "mkdir -p ~/lxon-blockchain"
    
    # Note: Since we don't have the actual LXON blockchain software,
    # this is a placeholder for where you would:
    # 1. Clone/download the LXON blockchain repository
    # 2. Configure it for chain ID $CHAIN_ID
    # 3. Start the blockchain node
    
    echo "   ⚠️  Placeholder: LXON blockchain software installation"
    echo "   Please provide the LXON blockchain software installation instructions"
    echo ""
    
    echo "   ✅ $NAME is ready for blockchain software installation"
    echo ""
done

echo "======================================================"
echo "✅ Blockchain node installation preparation complete"
echo "======================================================"
echo ""
echo "📋 Next Steps:"
echo "  1. Provide LXON blockchain software installation instructions"
echo "  2. Configure blockchain nodes for chain ID $CHAIN_ID"
echo "  3. Start blockchain nodes"
echo "  4. Configure JSON-RPC endpoints on ports 8546, 8547"
echo "  5. Test RPC connectivity"
echo ""