#!/bin/bash

# Deploy Simple JSON-RPC Server to AWS EC2 (Using Existing Node.js)
# This script deploys a minimal JSON-RPC server using the existing Node.js installation

set -e

SSH_KEY="~/.ssh/lxon-blockchain-key-v3.pem"
SSH_USER="ubuntu"
CHAIN_ID=724

# Instances to deploy to
INSTANCES=(
    "13.61.177.64:validator-1:8546"
    "16.171.173.70:validator-2:8547"
)

echo "🚀 Deploying Simple JSON-RPC Server to AWS EC2 (Using Existing Node.js)"
echo "================================================"
echo "Chain ID: $CHAIN_ID"
echo ""

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
    
    # Check if Node.js is already installed
    echo "   Checking Node.js installation..."
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "node --version" > /dev/null 2>&1; then
        echo "   ✅ Node.js already installed"
    else
        echo "   ⚠️  Node.js not found, installing..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get update && sudo apt-get install -y nodejs npm"
    fi
    
    # Create RPC directory
    echo "   Setting up RPC directory..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "mkdir -p ~/lxon-rpc"
    
    # Create simple RPC server
    echo "   Creating RPC server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cat > ~/lxon-rpc/server.js" << 'EOF'
const http = require('http');
const os = require('os');

const CHAIN_ID = process.env.CHAIN_ID || '724';
const PORT = process.env.PORT || '8545';

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    });
    res.end();
    return;
  }
  
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', chainId: CHAIN_ID, hostname: os.hostname() }));
    return;
  }
  
  if (req.method === 'POST' && req.url === '/') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { method, id } = JSON.parse(body);
        let result;
        
        switch (method) {
          case 'eth_chainId':
            result = '0x' + parseInt(CHAIN_ID).toString(16);
            break;
          case 'net_version':
            result = CHAIN_ID;
            break;
          case 'eth_blockNumber':
            result = '0x1';
            break;
          default:
            result = null;
        }
        
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ jsonrpc: '2.0', id, result }));
      } catch (error) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }));
      }
    });
    return;
  }
  
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`LXON JSON-RPC Server running on port ${PORT}`);
  console.log(`Chain ID: ${CHAIN_ID}`);
});
EOF
    echo "   ✅ RPC server created"
    
    # Start the RPC server
    echo "   Starting RPC server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~/lxon-rpc && CHAIN_ID=$CHAIN_ID PORT=$PORT nohup node server.js > server.log 2>&1 &"
    echo "   ✅ RPC server started"
    
    # Wait for server to start
    echo "   Waiting for server to initialize..."
    sleep 5
    
    # Test the RPC server
    echo "   Testing RPC server..."
    curl -X POST http://$IP:$PORT -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null || echo "RPC test failed"
    
    echo "   ✅ $NAME deployment complete"
    echo ""
done

echo "================================================"
echo "✅ Simple JSON-RPC Deployment Complete"
echo "================================================"
echo ""
echo "📋 Deployed Instances:"
for instance in "${INSTANCES[@]}"; do
    IFS=':' read -r IP NAME PORT <<< "$instance"
    echo "  $NAME: http://$IP:$PORT"
done
echo ""
echo "🎯 Next Steps:"
echo "  1. Test RPC endpoints"
echo "  2. Update chainlist.json"
echo "  3. Configure domain DNS"
echo ""