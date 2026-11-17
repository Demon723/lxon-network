# LXON Blockchain Infrastructure - CloudFormation Templates

This directory contains CloudFormation templates for deploying the LXON blockchain infrastructure on AWS.

## Templates

### 1. `lxon-validator-single.yaml`
Single-validator QBFT blockchain deployment with:
- VPC with public and private subnets
- NAT Gateway for private subnet outbound access
- EC2 instance with Hyperledger Besu
- CloudWatch monitoring and alarms
- AWS Backup for EBS volumes
- Encrypted EBS volumes (gp3)

**Use case:** Development/testing or bootstrap single-node deployment

### 2. `lxon-validator-multi-az.yaml`
Multi-validator QBFT blockchain deployment with:
- VPC with 3 private subnets across 3 AZs
- 3 validator instances (minimum for Byzantine fault tolerance)
- NAT Gateway for private subnet outbound access
- CloudWatch monitoring and alarms
- AWS Backup for all validator instances
- Encrypted EBS volumes (gp3)

**Use case:** Production deployment with Byzantine fault tolerance

### 3. `lxon-cloudtrail.yaml`
CloudTrail audit logging configuration with:
- S3 bucket for log storage (with lifecycle policies)
- KMS encryption for logs (optional)
- Multi-region trail
- Global service event logging
- Log file validation
- CloudWatch alarms for CloudTrail errors

**Use case:** Compliance and audit requirements

### 4. `lxon-infrastructure-master.yaml`
Master stack that orchestrates all components:
- Deploys validator stack (single-AZ or multi-AZ)
- Deploys CloudTrail stack (optional)
- Creates SNS topic for alarm notifications
- CloudWatch dashboard for monitoring
- Block production monitoring alarm

**Use case:** Complete infrastructure deployment

## Deployment

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Existing SSH key pair in the target region
3. S3 bucket name for CloudTrail (must be globally unique)
4. (Optional) SNS topic for alarm notifications

### Deploy Master Stack (Recommended)

```bash
aws cloudformation create-stack \
  --stack-name lxon-production \
  --template-body file://lxon-infrastructure-master.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=DeploymentType,ParameterValue=multi-az \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=KeyName,ParameterValue=your-key-pair \
    ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16 \
    ParameterKey=ChainId,ParameterValue=724 \
    ParameterKey=BackupRetentionDays,ParameterValue=30 \
    ParameterKey=CloudTrailBucketName,ParameterValue=lxon-cloudtrail-unique-name \
    ParameterKey=EnableCloudTrail,ParameterValue=true \
    ParameterKey=NotificationEmail,ParameterValue=alerts@example.com \
  --capabilities CAPABILITY_IAM \
  --region eu-north-1
```

### Deploy Individual Stacks

#### Single Validator
```bash
aws cloudformation create-stack \
  --stack-name lxon-validator-single \
  --template-body file://lxon-validator-single.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=KeyName,ParameterValue=your-key-pair \
    ParameterKey=ChainId,ParameterValue=724 \
    ParameterKey=BackupRetentionDays,ParameterValue=30 \
  --capabilities CAPABILITY_IAM \
  --region eu-north-1
```

#### Multi-AZ Validators
```bash
aws cloudformation create-stack \
  --stack-name lxon-validator-multi-az \
  --template-body file://lxon-validator-multi-az.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=KeyName,ParameterValue=your-key-pair \
    ParameterKey=ChainId,ParameterValue=724 \
    ParameterKey=BackupRetentionDays,ParameterValue=30 \
    ParameterKey=ValidatorCount,ParameterValue=3 \
  --capabilities CAPABILITY_IAM \
  --region eu-north-1
```

#### CloudTrail
```bash
aws cloudformation create-stack \
  --stack-name lxon-cloudtrail \
  --template-body file://lxon-cloudtrail.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=S3BucketName,ParameterValue=lxon-cloudtrail-unique-name \
    ParameterKey=IsMultiRegion,ParameterValue=true \
    ParameterKey=IncludeGlobalServiceEvents,ParameterValue=true \
  --capabilities CAPABILITY_IAM \
  --region eu-north-1
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| Environment | Environment name (dev/staging/prod) | production |
| DeploymentType | single-az or multi-az | multi-az |
| InstanceType | EC2 instance type | t3.medium |
| KeyName | SSH key pair name | Required |
| ChainId | Blockchain chain ID | 724 |
| BackupRetentionDays | Backup retention (7/14/30/60/90 days) | 30 |
| CloudTrailBucketName | S3 bucket for CloudTrail logs | Required |
| EnableCloudTrail | Enable CloudTrail | true |
| NotificationEmail | Email for alarms | Optional |

### Besu Configuration

The EC2 instances include a user data script that:
- Installs Hyperledger Besu v24.6.0
- Installs Java 21
- Installs CloudWatch Agent
- Configures CloudWatch metrics collection
- Installs Node.js and Web3.js

**Note:** The genesis file and validator keys must be manually configured after instance deployment.

## Monitoring

### CloudWatch Dashboard

Access the CloudWatch dashboard:
```
https://<region>.console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards:name=<environment>-lxon-blockchain
```

### Alarms

The following alarms are configured:
- CPU > 80% for 5 minutes
- Memory > 90% for 5 minutes
- Disk > 90% for 5 minutes
- Block production stalled (no blocks for 10 minutes)
- CloudTrail errors
- CloudTrail configuration changes

### Log Groups

- `lxon-blockchain/besu` - Besu application logs
- `lxon-blockchain/system` - System logs

## Backup

AWS Backup is configured with:
- Daily backups at 2 AM UTC
- Configurable retention (7-90 days)
- Encrypted EBS snapshots
- Cross-region replication (optional, requires additional configuration)

### Restore Procedure

1. Open AWS Backup console
2. Select the backup vault
3. Choose the recovery point
4. Restore to new EC2 instance
5. Update validator configuration if needed

## Security

### Network Security

- Validators in private subnets
- SSH access restricted to port 22
- P2P ports (30303 TCP/UDP) restricted to VPC CIDR
- RPC port (8545) not exposed on validators

### IAM Roles

- EC2 instances use IAM roles with least privilege
- CloudWatch Agent Server Policy
- Custom CloudWatch Logs policy
- Backup service role

### Encryption

- EBS volumes encrypted with AWS KMS
- CloudTrail logs encrypted (SSE-S3 or KMS)
- S3 bucket for CloudTrail logs with encryption enabled

## Disaster Recovery

### RTO/RPO

- **RTO (Recovery Time Objective):** 2-4 hours
- **RPO (Recovery Point Objective):** 24 hours (daily backups)

### Recovery Steps

1. Identify the failed instance
2. Restore from AWS Backup to new instance
3. Reconfigure networking/security groups
4. Update validator peers
5. Verify blockchain sync

## Cost Estimation

### Single Validator (eu-north-1)
- t3.medium: ~$30/month
- EBS 20GB gp3: ~$2/month
- NAT Gateway: ~$32/month
- CloudWatch: ~$2/month
- **Total: ~$66/month**

### Multi-AZ (3 validators)
- 3x t3.medium: ~$90/month
- 3x EBS 20GB gp3: ~$6/month
- NAT Gateway: ~$32/month
- CloudWatch: ~$6/month
- **Total: ~$134/month**

### CloudTrail
- S3 storage: ~$0.023/GB/month
- CloudTrail: Free
- **Total: ~$5-10/month**

## Troubleshooting

### Instance Not Starting
- Check CloudWatch logs for user data script errors
- Verify IAM role permissions
- Check security group rules

### Block Production Stalled
- Check validator logs in CloudWatch
- Verify QBFT configuration
- Check validator peer connectivity
- Review CloudWatch alarms

### Backup Failures
- Verify IAM role for AWS Backup
- Check EBS volume tags
- Review Backup service logs

## Well-Architected Compliance

This infrastructure addresses AWS Well-Architected Framework pillars:

### Operational Excellence
- ✅ Infrastructure as Code (CloudFormation)
- ✅ Automated monitoring (CloudWatch)
- ✅ Alarm notifications (SNS)
- ⚠️ Deployment automation (manual CloudFormation)

### Security
- ✅ IAM roles with least privilege
- ✅ Encryption at rest (EBS, S3)
- ✅ Network isolation (private subnets)
- ✅ Audit logging (CloudTrail)
- ⚠️ Secrets management (manual)

### Reliability
- ✅ Multi-AZ deployment (multi-az template)
- ✅ Automated backups (AWS Backup)
- ✅ Health monitoring (CloudWatch)
- ⚠️ Auto-scaling (not implemented for validators)

### Performance Efficiency
- ✅ Instance type selection (parameterized)
- ⚠️ Caching (not implemented)
- ⚠️ CDN (not implemented)

### Cost Optimization
- ✅ Backup lifecycle policies
- ⚠️ Reserved instances (not configured)
- ⚠️ Resource tagging (partial)

### Sustainability
- ⚠️ Graviton instances (not configured)
- ⚠️ Carbon footprint tracking (not implemented)

## Next Steps

1. Deploy the master stack for production
2. Configure Besu genesis and validator keys
3. Set up custom CloudWatch alarms for blockchain-specific metrics
4. Implement Secrets Manager for validator keys
5. Add CloudFront for RPC endpoint (optional)
6. Configure cross-region backup replication
7. Set up deployment pipeline (CodePipeline/CodeDeploy)
8. Implement automated testing
9. Add Load Balancer for RPC gateway (multi-AZ)
10. Configure DNS (Route 53) for blockchain endpoints

## References

- [Hyperledger Besu Documentation](https://docs.hyperledger.org/besu)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [QBFT Consensus](https://docs.hyperledger.org/besu/private-networks/how-to/configure/consensus/qbft)
