#!/bin/bash

# Deploy LXON Blockchain Node to AWS EC2 Instances (Simplified)
# This script builds and deploys the LXON blockchain software to the AWS instances

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

echo "🚀 Deploying LXON Blockchain Node to AWS EC2"
echo "================================================"
echo "Chain ID: $CHAIN_ID"
echo "Network: $NETWORK_NAME"
echo "Repository: $REPO_PATH"
echo ""

# Step 1: Build Docker image locally
echo "🏗️  Building LXON Blockchain Docker Image..."
cd "$REPO_PATH"
docker build -f docker/lxon-node.Dockerfile -t lxon-node:latest . 2>&1 | tail -20
echo "✅ Docker image built successfully"
echo ""

# Step 2: Deploy to each instance
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
    
    # Install Docker
    echo "   Installing Docker..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get update && sudo apt-get install -y docker.io docker-compose && sudo systemctl start docker && sudo systemctl enable docker && sudo usermod -aG docker ubuntu"
    echo "   ✅ Docker installed"
    
    # Create blockchain directory
    echo "   Setting up blockchain directory..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "mkdir -p ~/lxon-blockchain/data ~/lxon-blockchain/logs"
    
    # Transfer Docker image
    echo "   Transferring Docker image..."
    docker save lxon-node:latest | ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "docker load"
    echo "   ✅ Docker image transferred"
    
    # Create environment file
    echo "   Creating environment configuration..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cat > ~/lxon-blockchain/.env" << EOF
CHAIN_ID=$CHAIN_ID
NETWORK_NAME=$NETWORK_NAME
NODE_TYPE=$NAME
RPC_PORT=$PORT
P2P_PORT=30303
DATA_DIR=/app/data
LOGS_DIR=/app/logs
EOF
    echo "   ✅ Environment configuration created"
    
    # Create docker-compose file
    echo "   Creating docker-compose configuration..."
    cat > /tmp/docker-compose.yml << 'EOFCOMPOSE'
version: '3.8'
services:
  lxon-node:
    image: lxon-node:latest
    container_name: lxon-NODE_NAME
    restart: unless-stopped
    ports:
      - "PORT:8545"
      - "8546:8546"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - CHAIN_ID=CHAIN_ID
      - NETWORK_NAME=NETWORK_NAME
      - NODE_TYPE=NODE_NAME
      - RPC_PORT=PORT
    env_file:
      - .env
    networks:
      - lxon-network
networks:
  lxon-network:
    driver: bridge
EOFCOMPOSE
    
    # Replace placeholders
    sed "s/NODE_NAME/$NAME/g; s/PORT/$PORT/g; s/CHAIN_ID/$CHAIN_ID/g; s/NETWORK_NAME/$NETWORK_NAME/g" /tmp/docker-compose.yml > /tmp/docker-compose-$NAME.yml
    
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/docker-compose-$NAME.yml $SSH_USER@$IP:~/lxon-blockchain/docker-compose.yml
    echo "   ✅ Docker-compose configuration created"
    
    # Start the blockchain node
    echo "   Starting LXON blockchain node..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~/lxon-blockchain && docker-compose up -d"
    echo "   ✅ Blockchain node started"
    
    # Wait for node to start
    echo "   Waiting for node to initialize..."
    sleep 15
    
    # Check if node is running
    echo "   Checking node status..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~/lxon-blockchain && docker-compose ps"
    
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
echo "  1. Check node logs: ssh -i $SSH_KEY $SSH_USER@<IP> 'cd ~/lxon-blockchain && docker-compose logs -f'"
echo "  2. Test RPC endpoint: curl -X POST http://<IP>:<PORT> -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}'"
echo "  3. Verify chain ID: 724"
echo "  4. Update domain DNS to point to RPC node"
echo ""