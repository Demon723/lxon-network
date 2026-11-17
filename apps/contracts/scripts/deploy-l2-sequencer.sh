#!/bin/bash

# L2 Sequencer Deployment Script
# This script builds and deploys the L2 sequencer to AWS infrastructure

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "🚀 Deploying L2 Sequencer to Mainnet Infrastructure"
echo "📋 Chain ID: 724"
echo "🌐 L1 RPC: http://13.61.177.64:8546"

# Build the L2 sequencer
echo "📦 Building L2 Sequencer binary..."
cargo build --release -p l2-sequencer

# Check if build was successful
if [ ! -f "target/release/l2-sequencer" ]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi

echo "✅ Build successful"
echo "📦 Binary location: target/release/l2-sequencer"

# Configuration for L2 sequencer
L2_CONFIG='{
  "l1_rpc_url": "http://13.61.177.64:8546",
  "chain_id": 724,
  "batch_size": 1000,
  "batch_interval_ms": 400,
  "max_mempool": 1000000,
  "signer_key_path": "/etc/lxon/l2-sequencer-key.json"
}'

echo "🔧 L2 Sequencer Configuration:"
echo "$L2_CONFIG"

# Deployment steps (placeholder for actual infrastructure deployment)
echo "🚀 Deployment steps:"
echo "   1. Upload binary to AWS EC2 instances"
echo "   2. Install systemd service"
echo "   3. Configure environment variables"
echo "   4. Start L2 sequencer service"
echo "   5. Verify L2 sequencer health"

# Create deployment directory structure
echo "📁 Creating deployment directory structure..."
mkdir -p deployments/l2-sequencer

# Save configuration
echo "$L2_CONFIG" > deployments/l2-sequencer/config.json

echo "✅ L2 Sequencer deployment preparation complete"
echo "📋 Next steps:"
echo "   1. Upload target/release/l2-sequencer to AWS instances"
echo "   2. Deploy configuration to /etc/lxon/l2-sequencer.json"
echo "   3. Create systemd service file"
echo "   4. Start the service"

echo "📄 Deployment assets:"
echo "   - Binary: target/release/l2-sequencer"
echo "   - Config: deployments/l2-sequencer/config.json"