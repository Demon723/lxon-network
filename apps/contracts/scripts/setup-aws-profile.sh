#!/bin/bash

# AWS Profile Setup Script for LXON Mainnet Deployment
# This script helps configure AWS credentials for mainnet deployment

set -e

echo "🚀 AWS Profile Setup for LXON Mainnet Deployment"
echo "======================================================"
echo ""

PROFILE_NAME="lxon-mainnet"
AWS_REGION="us-east-1"

echo "📋 AWS Profile Configuration"
echo "  Profile Name: $PROFILE_NAME"
echo "  Region: $AWS_REGION"
echo ""

# Check if profile already exists
if aws configure list-profiles | grep -q "^$PROFILE_NAME$"; then
    echo "✅ Profile '$PROFILE_NAME' already exists"
    echo ""
    echo "Current configuration:"
    aws configure get --profile $PROFILE_NAME aws_access_key_id
    aws configure get --profile $PROFILE_NAME aws_secret_access_key
    aws configure get --profile $PROFILE_NAME region
    aws configure get --profile $PROFILE_NAME output
    echo ""
    read -p "Do you want to update this profile? (yes/no): " update_profile
    
    if [ "$update_profile" != "yes" ]; then
        echo "❌ Setup cancelled"
        exit 0
    fi
fi

echo "🔐 Enter AWS Credentials"
echo "You can find these in your AWS IAM Console"
echo ""

read -p "AWS Access Key ID: " access_key
read -p "AWS Secret Access Key: " secret_key
read -p "Default Region [$AWS_REGION]: " region
region=${region:-$AWS_REGION}
read -p "Default Output format [json]: " output
output=${output:-json}

echo ""
echo "⚙️  Configuring AWS profile..."

# Configure the profile
aws configure set --profile $PROFILE_NAME aws_access_key_id "$access_key"
aws configure set --profile $PROFILE_NAME aws_secret_access_key "$secret_key"
aws configure set --profile $PROFILE_NAME region "$region"
aws configure set --profile $PROFILE_NAME output "$output"

echo ""
echo "✅ AWS Profile '$PROFILE_NAME' configured successfully"
echo ""

# Verify the configuration
echo "🔍 Verifying configuration..."
if aws sts get-caller-identity --profile $PROFILE_NAME > /dev/null 2>&1; then
    echo "✅ AWS credentials verified"
    whoami=$(aws sts get-caller-identity --profile $PROFILE_NAME --query Account --output text)
    echo "   Account: $whoami"
else
    echo "❌ AWS credentials verification failed"
    echo "   Please check your credentials and try again"
    exit 1
fi

echo ""
echo "📋 Next Steps:"
echo "  1. Set the AWS profile for deployment:"
echo "     export AWS_PROFILE=$PROFILE_NAME"
echo ""
echo "  2. Run the mainnet deployment:"
echo "     npx hardhat run scripts/deploy-mainnet-aws.ts --network lxon"
echo ""
echo "  3. Or run the full test suite:"
echo "     npx hardhat test test/mainnet/MainnetDeployment.test.ts --network lxon"
echo ""
echo "======================================================"
echo "✅ AWS Profile Setup Complete"
echo "======================================================"