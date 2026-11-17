# IAM Permissions Required for CloudFormation Deployment

> **Superseded 2026-10-21 by [`POLICY_GRANT_REQUEST.md`](POLICY_GRANT_REQUEST.md)** and
> [`lxon-deploy-policy.json`](lxon-deploy-policy.json). This file asks for
> `cloudformation:*`, `ec2:*` and unscoped `iam:PassRole`; the replacement is derived from the
> 32 resource types the templates actually declare, scopes CloudFormation to `stack/lxon-*`
> and PassRole to `role/lxon-*`, and records the measured per-service probe results. Kept for
> history; its opening claim is still correct.

The IAM user `devin-blockchain-deployer` (ARN: `arn:aws:iam::404268099234:user/devin-blockchain-deployer`) lacks the necessary permissions to deploy CloudFormation stacks.

## Required Permissions

### CloudFormation Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### EC2 Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### S3 Permissions (for CloudTrail)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicy",
        "s3:PutBucketEncryption",
        "s3:PutBucketVersioning",
        "s3:PutLifecycleConfiguration",
        "s3:PutPublicAccessBlock"
      ],
      "Resource": "*"
    }
  ]
}
```

### CloudWatch Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*",
        "logs:*",
        "events:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Backup Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "backup:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### CloudTrail Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudtrail:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### SNS Permissions (for alarms)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### KMS Permissions (for CloudTrail encryption)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:EnableKey",
        "kms:GenerateDataKey*",
        "kms:PutKeyPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Fix: Administrator Access

For immediate deployment, you can grant AdministratorAccess to the user:

```bash
aws iam attach-user-policy \
  --user-name devin-blockchain-deployer \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Warning:** AdministratorAccess grants full access to all AWS resources. Use only for testing or in development environments.

## Recommended: Custom Policy

Create a custom policy with the minimum required permissions:

```bash
aws iam create-policy \
  --policy-name LXONCloudFormationDeployer \
  --policy-document file://policy.json
```

Then attach it to the user:

```bash
aws iam attach-user-policy \
  --user-name devin-blockchain-deployer \
  --policy-arn arn:aws:iam::404268099234:policy/LXONCloudFormationDeployer
```

## Alternative: Use AWS Console

If you cannot modify IAM permissions, you can deploy the stack manually using the AWS Console:

1. Open AWS CloudFormation console in eu-north-1
2. Click "Create stack"
3. Choose "Upload a template file"
4. Upload `lxon-validator-single.yaml`
5. Configure parameters:
   - Environment: production
   - InstanceType: t3.medium
   - KeyName: lxon-blockchain-eu-north-1
   - VpcCidr: 10.0.0.0/16
   - ChainId: 724
   - BackupRetentionDays: 30
6. Acknowledge IAM capabilities
7. Create stack

## Alternative: Use Root Account

The root account has all permissions and can deploy the stack. However, this is not recommended for security reasons.

## Current Status

- ✅ CloudFormation templates created and validated
- ❌ IAM permissions insufficient for automated deployment
- ⏳ Awaiting IAM permission fix or manual deployment

## Next Steps

1. Grant IAM permissions to `devin-blockchain-deployer` user
2. Retry CloudFormation deployment
3. Or deploy manually via AWS Console
4. Once deployed, proceed with Besu QBFT configuration update
