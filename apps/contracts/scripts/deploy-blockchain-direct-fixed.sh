#!/bin/bash

# Deploy LXON Blockchain Node to AWS EC2 Instances (Direct Build)
# This script deploys and builds the LXON blockchain directly on EC2 instances

set -e

SSH_KEY="~/.ssh/lxon-blockchain-key-v3.pem"
SSH_USER="ubuntu"
CHAIN_ID=724
NETWORK_NAME="lxon"
REPO_PATH="/Users/adikamble/LXON/LXON"

# Instances to deploy to
INSTANCES=(
    "13.61.177.64:validator-1:8546"
    "16.171.173.70:validator-2:8547"
)

echo "🚀 Deploying LXON Blockchain Node to AWS EC2 (Direct Build)"
echo "================================================"
echo "Chain ID: $CHAIN_ID"
echo "Network: $NETWORK_NAME"
echo "Repository: $REPO_PATH"
echo ""

# Step 1: First, let's create a simple blockchain node on the instances
for instance in "${INSTANCES[@]}"; do
    IFS=':' read -r IP NAME PORT <<< "$instance"
    
    echo "📦 Deploying to $NAME ($IP)..."
    
    # Test SSH connection
    echo "   Testing SSH connection..."
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$IP "echo 'SSH successful'" > /dev/null 2>&1; then
        echo "   ❌ SSH connection failed"
        continue
    fi
    echo "   ✅ SSH connection successful"
    
    # Install Node.js and dependencies
    echo "   Installing Node.js and dependencies..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get update && sudo apt-get install -y nodejs npm git curl && curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo npm install -g pnpm"
    echo "   ✅ Node.js and dependencies installed"
    
    # Clone the repository
    echo "   Cloning LXON repository..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~ && git clone https://github.com/lxon-blockchain/lxon.git lxon-repo || cd ~/lxon-repo && git pull"
    echo "   ✅ Repository cloned"
    
    # Build the blockchain
    echo "   Building LXON blockchain..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~/lxon-repo && pnpm install && pnpm --filter lxon-blockchain build"
    echo "   ✅ Blockchain built"
    
    # Create blockchain directory
    echo "   Setting up blockchain directory..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "mkdir -p ~/lxon-blockchain/data ~/lxon-blockchain/logs"
    
    # Create environment file
    echo "   Creating environment configuration..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "echo 'CHAIN_ID=$CHAIN_ID' > ~/lxon-blockchain/.env && echo 'NETWORK_NAME=$NETWORK_NAME' >> ~/lxon-blockchain/.env && echo 'NODE_TYPE=$NAME' >> ~/lxon-blockchain/.env && echo 'RPC_PORT=$PORT' >> ~/lxon-blockchain/.env && echo 'P2P_PORT=30303' >> ~/lxon-blockchain/.env && echo 'DATA_DIR=/app/data' >> ~/lxon-blockchain/.env && echo 'LOGS_DIR=/app/logs' >> ~/lxon-blockchain/.env"
    echo "   ✅ Environment configuration created"
    
    # Create startup script
    echo "   Creating startup script..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "echo '#!/bin/bash' > ~/lxon-blockchain/start.sh && echo 'cd ~/lxon-repo' >> ~/lxon-blockchain/start.sh && echo 'export CHAIN_ID=\$(cat ~/lxon-blockchain/.env | grep CHAIN_ID | cut -d= -f2)' >> ~/lxon-blockchain/start.sh && echo 'export NETWORK_NAME=\$(cat ~/lxon-blockchain/.env | grep NETWORK_NAME | cut -d= -f2)' >> ~/lxon-blockchain/start.sh && echo 'export NODE_TYPE=\$(cat ~/lxon-blockchain/.env | grep NODE_TYPE | cut -d= -f2)' >> ~/lxon-blockchain/start.sh && echo 'export RPC_PORT=\$(cat ~/lxon-blockchain/.env | grep RPC_PORT | cut -d= -f2)' >> ~/lxon-blockchain/start.sh && echo 'node apps/lxon-blockchain/dist/rpc/node.js' >> ~/lxon-blockchain/start.sh && chmod +x ~/lxon-blockchain/start.sh"
    echo "   ✅ Startup script created"
    
    # Start the blockchain node in background
    echo "   Starting LXON blockchain node..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "nohup ~/lxon-blockchain/start.sh > ~/lxon-blockchain/logs/node.log 2>&1 &"
    echo "   ✅ Blockchain node started"
    
    # Wait for node to start
    echo "   Waiting for node to initialize..."
    sleep 20
    
    # Check if node is running
    echo "   Checking node status..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "ps aux | grep node | grep blockchain || echo 'Node process not found'"
    
    echo "   ✅ $NAME deployment complete"
    echo ""
done

echo "================================================"
echo "✅ LXON Blockchain Deployment Complete"
echo "================================================"
echo ""
echo "📋 Deployed Instances:"
for instance in "${INSTANCES[@]}"; do
    IFS=':' read -r IP NAME PORT <<< "$instance"
    echo "  $NAME: http://$IP:$PORT"
done
echo ""
echo "🎯 Next Steps:"
echo "  1. Check node logs: ssh -i $SSH_KEY $SSH_USER@<IP> 'tail -f ~/lxon-blockchain/logs/node.log'"
echo "  2. Test RPC endpoint: curl -X POST http://<IP>:<PORT> -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}'"
echo "  3. Verify chain ID: 724"
echo "  4. Update domain DNS to point to RPC node"
echo ""