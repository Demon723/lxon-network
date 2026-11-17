#!/bin/bash

# Post-Quantum Security Deployment Script
# This script builds and deploys the post-quantum security components

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "🔐 Deploying Post-Quantum Security Components"
echo "📋 Chain ID: 724"
echo "🔐 PQ Security: Hybrid Cryptography Implementation"

# Build the PQ security library
echo "📦 Building PQ Security library..."
cargo build --release -p crypto-pqc

# Check if build was successful
if [ ! -f "target/release/libcrypto_pqc.a" ]; then
    echo "❌ Build failed - library not found"
    exit 1
fi

echo "✅ Build successful"
echo "📦 Library location: target/release/libcrypto_pqc.a"

# Configuration for PQ security
PQ_CONFIG='{
  "hybrid_crypto": {
    "enabled": true,
    "algorithms": [
      "ed25519",
      "x25519",
      "kyber768",
      "dilithium3"
    ]
  },
  "signature_verification": {
    "satellite_signatures": true,
    "pq_enabled": true,
    "hybrid_mode": true
  },
  "key_encapsulation": {
    "enabled": true,
    "default_algorithm": "kyber768"
  }
}'

echo "🔧 PQ Security Configuration:"
echo "$PQ_CONFIG"

# Deployment steps
echo "🚀 Deployment steps:"
echo "   1. Upload library to all nodes requiring PQ capabilities"
echo "   2. Install hybrid signature verification libraries"
echo "   3. Configure PQ algorithms and parameters"
echo "   4. Update signature verification in L1/L2/L3"
echo "   5. Test PQ signature verification"

# Create deployment directory structure
echo "📁 Creating deployment directory structure..."
mkdir -p deployments/pq-security

# Save configuration
echo "$PQ_CONFIG" > deployments/pq-security/config.json

echo "✅ PQ Security deployment preparation complete"
echo "📋 Next steps:"
echo "   1. Upload target/release/libcrypto_pqc.a to all nodes"
echo "   2. Deploy configuration to /etc/lxon/pq-security.json"
echo "   3. Update L1/L2/L3 signature verification to use PQ library"
echo "   4. Restart nodes with PQ capabilities"

echo "📄 Deployment assets:"
echo "   - Library: target/release/libcrypto_pqc.a"
echo "   - Config: deployments/pq-security/config.json"