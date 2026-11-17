# LXON Blockchain Infrastructure as Code

## Overview

This directory contains CloudFormation templates for deploying the LXON blockchain infrastructure on AWS, including single-validator and multi-AZ architectures, as well as an automated deployment pipeline.

## Templates

### 1. Single Validator (`lxon-validator-single.yaml`)

**Use Case:** Development or initial production deployment with a single validator node.

**Resources:**
- VPC with public and private subnets
- EC2 instance (t3.medium default) in private subnet
- NAT Gateway for outbound access
- Security groups (SSH, P2P)
- IAM roles with CloudWatch permissions
- CloudWatch Agent configuration
- CloudWatch Log Groups
- CloudWatch Alarms (CPU, memory, disk)
- AWS Backup Vault and Plan
- EBS volume (20GB, encrypted, gp3)

**Parameters:**
- `Environment`: development/staging/production
- `InstanceType`: t3.medium, t3.large, t3.xlarge, m5.large, m5.xlarge
- `KeyName`: SSH key pair name
- `ChainId`: Blockchain chain ID (default: 724)
- `BackupRetentionDays`: 7/14/30/60/90 (default: 30)

**Deployment:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-validator-production \
  --template-file infrastructure/cloudformation/lxon-validator-single.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=KeyName,ParameterValue=your-key-name \
  --capabilities CAPABILITY_IAM
```

### 2. Multi-AZ Validators (`lxon-validator-multi-az.yaml`)

**Use Case:** Production deployment with Byzantine fault tolerance (3 validators across 3 AZs).

**Resources:**
- VPC with 3 private subnets (one per AZ)
- 3 EC2 instances (one per private subnet)
- Public subnet for RPC gateway
- NAT Gateway for outbound access
- Security groups (validators, RPC gateway)
- IAM roles with CloudWatch permissions
- CloudWatch Log Groups
- CloudWatch Composite Alarms (all validators)
- AWS Backup Vault and Plan (all validators)
- EBS volumes (20GB, encrypted, gp3 each)

**Parameters:**
- `Environment`: development/staging/production
- `InstanceType`: t3.medium, t3.large, t3.xlarge, m5.large, m5.xlarge
- `KeyName`: SSH key pair name
- `ChainId`: Blockchain chain ID (default: 724)
- `ValidatorCount`: 3/4/5 (default: 3)
- `BackupRetentionDays`: 7/14/30/60/90 (default: 30)

**Deployment:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-validators-production \
  --template-file infrastructure/cloudformation/lxon-validator-multi-az.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=KeyName,ParameterValue=your-key-name \
  --parameters ParameterKey=ValidatorCount,ParameterValue=3 \
  --capabilities CAPABILITY_IAM
```

### 3. Deployment Pipeline (`lxon-pipeline.yaml`)

**Use Case:** Automated CI/CD pipeline for building and deploying LXON blockchain components.

**Resources:**
- S3 artifact bucket (versioned, encrypted)
- CodeBuild project (GitHub integration)
- CodeDeploy application and deployment group
- CodePipeline (Source → Build → Deploy)
- IAM roles for CodeBuild, CodeDeploy, CodePipeline
- CloudWatch Alarms (pipeline, build, deployment failures)

**Parameters:**
- `Environment`: development/staging/production
- `GitHubOwner`: GitHub repository owner
- `GitHubRepo`: GitHub repository name
- `GitHubBranch`: Branch to deploy (default: main)
- `GitHubToken`: GitHub personal access token (NoEcho)
- `VpcId`: VPC ID (exported from validator stack)
- `PrivateSubnetIds`: Private subnet IDs (exported from validator stack)

**Deployment:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-pipeline-production \
  --template-file infrastructure/cloudformation/lxon-pipeline.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=GitHubOwner,ParameterValue=adikamble \
  --parameters ParameterKey=GitHubRepo,ParameterValue=LXON \
  --parameters ParameterKey=GitHubBranch,ParameterValue=main \
  --parameters ParameterKey=GitHubToken,ParameterValue=your-github-token \
  --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
  --parameters ParameterKey=PrivateSubnetIds,ParameterValue=subnet-xxx,subnet-yyy \
  --capabilities CAPABILITY_IAM
```

## Build Specification

The `buildspec.yml` file defines the build process for CodeBuild:

**Phases:**
1. **Install:** Install Node.js 20, pnpm, and dependencies
2. **Pre-build:** Run tests
3. **Build:** Build contracts and compile Solidity
4. **Post-build:** Export build artifacts

**Artifacts:**
- `dist/**/*` - Build output
- `artifacts/**/*` - Compiled contracts
- `apps/contracts/**/*` - Contract source

**Cache:**
- `node_modules/**/*`
- `.pnpm-store/**/*`

## Architecture

### Single Validator Architecture

```
                    Internet
                       |
                [Internet Gateway]
                       |
              [Public Subnet 10.0.1.0/24]
                       |
                [NAT Gateway]
                       |
              [Private Subnet 10.0.2.0/24]
                       |
            [Validator EC2 Instance]
                       |
         [Besu QBFT + CloudWatch Agent]
```

### Multi-AZ Architecture

```
                    Internet
                       |
                [Internet Gateway]
                       |
              [Public Subnet 10.0.10.0/24]
                       |
                [NAT Gateway]
                       |
    -----------------------------------
    |                 |                 |
[Private Subnet 1] [Private Subnet 2] [Private Subnet 3]
[10.0.1.0/24]   [10.0.2.0/24]   [10.0.3.0/24]
     |                 |                 |
[Validator 1]   [Validator 2]   [Validator 3]
[AZ A]         [AZ B]         [AZ C]
```

### Deployment Pipeline Architecture

```
GitHub Repository
       |
[CodePipeline]
       |
    [Source Stage]
       |
    [Build Stage]
       |
 [CodeBuild]
       |
 [Build Artifacts → S3]
       |
   [Deploy Stage]
       |
 [CodeDeploy]
       |
 [EC2 Instances]
```

## Security Features

### Network Security
- VPC isolation
- Private subnets for validators
- NAT Gateway for outbound access (no direct internet access)
- Security groups limiting ingress (SSH, P2P only within VPC)
- Encrypted EBS volumes

### IAM Security
- Least privilege IAM roles
- Service-specific roles (CodeBuild, CodeDeploy, Backup)
- No long-lived access keys on instances
- Instance profiles for EC2

### Data Security
- EBS encryption at rest (gp3 with encryption)
- S3 bucket encryption (AES256)
- S3 bucket policy (public access blocked)
- Versioned S3 artifacts

### Monitoring & Alerting
- CloudWatch metrics (CPU, memory, disk)
- CloudWatch Logs (system, Besu)
- CloudWatch Alarms (threshold-based)
- SNS notifications (requires manual configuration)

## Cost Estimates

### Single Validator
- EC2 t3.medium: ~$30-40/month
- EBS 20GB gp3: ~$2-3/month
- NAT Gateway: ~$20-30/month
- CloudWatch Logs: ~$0.50-1/month
- CloudWatch Metrics: ~$0.50-1/month
- AWS Backup: ~$5-10/month
- **Total:** ~$58-85/month

### Multi-AZ (3 Validators)
- EC2 t3.medium × 3: ~$90-120/month
- EBS 20GB gp3 × 3: ~$6-9/month
- NAT Gateway: ~$20-30/month
- CloudWatch Logs: ~$1-2/month
- CloudWatch Metrics: ~$1-2/month
- AWS Backup: ~$15-30/month
- **Total:** ~$133-193/month

### Deployment Pipeline
- CodeBuild: ~$0.50-1/build
- S3 Storage: ~$0.50-1/month
- CodePipeline: ~$1/month
- **Total:** ~$2-3/month + build costs

## Deployment Steps

### Initial Deployment (Single Validator)

1. **Deploy Single Validator Stack:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-validator-prod \
  --template-file infrastructure/cloudformation/lxon-validator-single.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=KeyName,ParameterValue=your-key \
  --capabilities CAPABILITY_IAM
```

2. **Wait for Stack Completion:**
```bash
aws cloudformation wait stack-create-complete \
  --stack-name lxon-validator-prod
```

3. **Get Validator Instance IP:**
```bash
aws cloudformation describe-stacks \
  --stack-name lxon-validator-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`ValidatorPrivateIP`].OutputValue'
```

4. **SSH to Validator:**
```bash
ssh -i your-key.pem ubuntu@<validator-ip>
```

5. **Configure Besu:**
- Install Hyperledger Besu
- Configure QBFT genesis
- Start Besu service
- Verify block production

### Upgrade to Multi-AZ

1. **Deploy Multi-AZ Stack:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-validators-prod \
  --template-file infrastructure/cloudformation/lxon-validator-multi-az.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=KeyName,ParameterValue=your-key \
  --parameters ParameterKey=ValidatorCount,ParameterValue=3 \
  --capabilities CAPABILITY_IAM
```

2. **Get Validator IPs:**
```bash
aws cloudformation describe-stacks \
  --stack-name lxon-validators-prod \
  --query 'Stacks[0].Outputs'
```

3. **Configure QBFT with 3 Validators:**
- Update genesis with 3 validator addresses
- Distribute genesis to all validators
- Start all validators
- Verify consensus

### Deploy Pipeline

1. **Deploy Pipeline Stack:**
```bash
aws cloudformation create-stack \
  --stack-name lxon-pipeline-prod \
  --template-file infrastructure/cloudformation/lxon-pipeline.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production \
  --parameters ParameterKey=GitHubOwner,ParameterValue=adikamble \
  --parameters ParameterKey=GitHubRepo,ParameterValue=LXON \
  --parameters ParameterKey=GitHubBranch,ParameterValue=main \
  --parameters ParameterKey=GitHubToken,ParameterValue=your-token \
  --parameters ParameterKey=VpcId,ParameterValue=<vpc-id> \
  --parameters ParameterKey=PrivateSubnetIds,ParameterValue=<subnet-ids> \
  --capabilities CAPABILITY_IAM
```

2. **Push to GitHub:**
```bash
git add .
git commit -m "feat: add infrastructure as code"
git push origin main
```

3. **Monitor Pipeline:**
```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name production-lxon-pipeline
```

## Troubleshooting

### Stack Creation Fails
- Check IAM permissions
- Verify parameter values
- Check CloudFormation events

### Instance Not Accessible
- Verify security group rules
- Check SSH key pair
- Verify instance is running

### Pipeline Fails
- Check GitHub token permissions
- Verify buildspec.yml syntax
- Check CodeBuild logs

### Backup Not Working
- Verify IAM role permissions
- Check backup plan schedule
- Verify instance profile attachment

## Best Practices

1. **Always use versioned artifacts** in S3
2. **Enable encryption** on all EBS volumes and S3 buckets
3. **Use least privilege IAM** roles
4. **Monitor alarms** and set up SNS notifications
5. **Test backups** regularly (restore to a new instance)
6. **Use parameter stores** for sensitive data (not plain text)
7. **Tag all resources** for cost allocation
8. **Review costs** monthly and optimize

## Maintenance

### Monthly
- Review CloudWatch metrics and alarms
- Check backup retention
- Review AWS Cost Explorer
- Update AMI mappings if needed

### Quarterly
- Test backup restore procedure
- Review security groups
- Update CloudFormation templates
- Disaster recovery drill

### Annually
- Review instance types (right-sizing)
- Review region deployment
- Cost optimization review
- Security audit

## Next Steps

1. **Add SNS notifications** for CloudWatch alarms
2. **Add AWS Systems Manager** for parameter storage
3. **Add AWS Secrets Manager** for sensitive data
4. **Add Terraform/CDK alternative** templates
5. **Add blue/green deployment** configuration
6. **Add load balancer** for RPC gateway
7. **Add SSL/TLS** for RPC endpoint
8. **Add VPC peering** for multi-region deployment

## Documentation

- AWS CloudFormation: https://docs.aws.amazon.com/cloudformation/
- AWS CodeBuild: https://docs.aws.amazon.com/codebuild/
- AWS CodeDeploy: https://docs.aws.amazon.com/codedeploy/
- AWS CodePipeline: https://docs.aws.amazon.com/codepipeline/
- AWS Backup: https://docs.aws.amazon.com/aws-backup/
- Hyperledger Besu: https://besu.hyperledger.org/
