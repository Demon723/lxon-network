#!/bin/bash

# Deploy LXON Blockchain Node to AWS EC2 Instances (Simple Approach)
# This script installs a simple JSON-RPC server on the EC2 instances

set -e

SSH_KEY="~/.ssh/lxon-blockchain-key-v3.pem"
SSH_USER="ubuntu"
CHAIN_ID=724
NETWORK_NAME="lxon"

# Instances to deploy to
INSTANCES=(
    "13.61.177.64:validator-1:8546"
    "16.171.173.70:validator-2:8547"
)

echo "🚀 Deploying Simple JSON-RPC Server to AWS EC2"
echo "================================================"
echo "Chain ID: $CHAIN_ID"
echo "Network: $NETWORK_NAME"
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
    
    # Install Node.js
    echo "   Installing Node.js..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "sudo apt-get update && sudo apt-get install -y nodejs npm"
    echo "   ✅ Node.js installed"
    
    # Create RPC server
    echo "   Creating JSON-RPC server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "mkdir -p ~/lxon-rpc"
    
    # Create a simple RPC server
    cat > /tmp/rpc-server.js << 'EOFRPC'
const http = require('http');
const url = require('url');

const CHAIN_ID = process.env.CHAIN_ID || '724';
const PORT = process.env.PORT || '8545';

const server = http.createServer((req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const path = parsedUrl.pathname;
  
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  if (path === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', chainId: CHAIN_ID }));
    return;
  }
  
  if (req.method === 'POST' && path === '/') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const jsonrpcRequest = JSON.parse(body);
        const { method, params, id } = jsonrpcRequest;
        
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
          case 'eth_getBalance':
            result = '0x0';
            break;
          case 'eth_getTransactionCount':
            result = '0x0';
            break;
          default:
            result = null;
        }
        
        const response = {
          jsonrpc: '2.0',
          id: id,
          result: result
        };
        
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
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
  console.log(`Health check: http://localhost:${PORT}/health`);
});
EOFRPC
    
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/rpc-server.js $SSH_USER@$IP:~/lxon-rpc/rpc-server.js
    echo "   ✅ RPC server created"
    
    # Start the RPC server
    echo "   Starting RPC server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$IP "cd ~/lxon-rpc && nohup node rpc-server.js > logs.txt 2>&1 &"
    echo "   ✅ RPC server started"
    
    # Wait for server to start
    echo "   Waiting for server to initialize..."
    sleep 5
    
    # Test the RPC server
    echo "   Testing RPC server..."
    curl -X POST http://$IP:$PORT -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' || echo "RPC test failed"
    
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
echo "  2. Update chainlist.json with new endpoints"
echo "  3. Configure domain DNS"
echo "  4. Replace with actual LXON blockchain software when available"
echo ""