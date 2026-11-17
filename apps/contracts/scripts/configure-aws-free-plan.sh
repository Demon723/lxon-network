#!/bin/bash

# AWS Configuration for Free Plan
# Manual configuration script for AWS free tier users

set -e

echo "🚀 AWS Configuration for Free Plan"
echo "======================================================"
echo ""

CREDENTIALS_FILE="$HOME/.aws/credentials"
CONFIG_FILE="$HOME/.aws/config"

echo "📋 AWS Free Plan Configuration"
echo "  Profile: lxon-mainnet"
echo "  Region: eu-north-1"
echo "  RAM Share: arn:aws:ram:eu-north-1:316742356862:resource-share/0c51f76f-d8ad-468d-ba93-ec2fa1084a7e"
echo ""

# Create .aws directory if it doesn't exist
mkdir -p ~/.aws

echo "🔐 Step 1: Configure AWS Credentials"
echo "  Please open $CREDENTIALS_FILE and replace the placeholder values:"
echo ""
echo "  [lxon-mainnet]"
echo "  aws_access_key_id = YOUR_ACCESS_KEY_ID"
echo "  aws_secret_access_key = YOUR_SECRET_ACCESS_KEY"
echo ""

read -p "Press Enter to open the credentials file..."

# Open the file in the default editor
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$CREDENTIALS_FILE"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    xdg-open "$CREDENTIALS_FILE" 2>/dev/null || nano "$CREDENTIALS_FILE"
else
    nano "$CREDENTIALS_FILE"
fi

echo ""
echo "⚙️  Step 2: AWS Config File"
echo "  Config file already created at $CONFIG_FILE"
echo "  Region: eu-north-1"
echo "  Output: json"
echo ""

echo "🔍 Step 3: Verification"
echo "  After updating credentials, run:"
echo "  export AWS_PROFILE=lxon-mainnet"
echo "  aws sts get-caller-identity"
echo ""

echo "📋 Step 4: Test Deployment"
echo "  cd /Users/adikamble/LXON/LXON/apps/contracts"
echo "  export AWS_PROFILE=lxon-mainnet"
echo "  npx ts-node scripts/deploy-mainnet-offline.ts"
echo ""

echo "═".repeat(70)
echo "✅ Configuration Instructions Complete"
echo "═".repeat(70)
echo ""
echo "📝 Summary:"
echo "  1. Edit ~/.aws/credentials with your Access Key ID and Secret Access Key"
echo "  2. Set AWS_PROFILE=lxon-mainnet environment variable"
echo "  3. Run deployment script to verify configuration"
echo ""
echo "💡 Free Plan Tips:"
echo "  - Check your AWS Free Tier limits at https://aws.amazon.com/free/"
echo "  - Monitor your usage to avoid unexpected charges"
echo "  - RAM share allows access to shared resources in eu-north-1"
echo ""