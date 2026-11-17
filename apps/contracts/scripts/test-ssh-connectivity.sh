#!/bin/bash

# Test SSH connectivity to the deployed AWS instances

SSH_KEY="~/.ssh/lxon-blockchain-key-v3.pem"
SSH_USER="ubuntu"

echo "🔍 Testing SSH Connectivity to AWS Instances"
echo "=============================================="
echo ""

# Test validator-1
echo "Testing lxon-validator-1 (13.61.177.64)..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@13.61.177.64 "echo 'SSH successful' && uname -a" 2>&1; then
    echo "✅ lxon-validator-1: SSH connection successful"
else
    echo "❌ lxon-validator-1: SSH connection failed"
fi
echo ""

# Test validator-2
echo "Testing lxon-validator-2 (16.171.173.70)..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@16.171.173.70 "echo 'SSH successful' && uname -a" 2>&1; then
    echo "✅ lxon-validator-2: SSH connection successful"
else
    echo "❌ lxon-validator-2: SSH connection failed"
fi
echo ""

echo "=============================================="
echo "SSH connectivity test complete"
echo "=============================================="