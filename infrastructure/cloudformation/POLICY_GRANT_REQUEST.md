# Phase 3 / 6 — what is blocked, what is not, and what the templates would actually do

Prepared 2026-10-21. Scope: read-only probes plus an offline audit of the five templates in
this directory. **Nothing was deployed and nothing in AWS was modified.**

## 1. Identity and the measured permission boundary

`aws sts get-caller-identity` → `AIDAV4ICBU2RB2P2O7IJJ` in account `404268099234`,
user `devin-blockchain-deployer`.

Verdicts below are taken from the **CLI exit code**, not from pattern-matching output. That
matters: an earlier version of this probe looked at truncated stdout for the word
`AccessDenied` and reported every service as ALLOWED, including CloudFormation, which is
the exact opposite of the truth.

| action probed | verdict | evidence |
|---|---|---|
| `cloudformation:ListStacks` | **DENIED** | `AccessDenied … User: arn:aws:iam::404268099234:user/devin-blockchain-deployer is not authorized to perform: cloudformation:ListStacks` |
| `cloudformation:GetTemplateSummary` | **DENIED** | `AccessDenied when calling the GetTemplateSummary operation` |
| `cloudformation:ValidateTemplate` | **DENIED** | `AccessDenied when calling the ValidateTemplate operation` |
| `cloudtrail:DescribeTrails` | **DENIED** | `AccessDeniedException … DescribeTrails` |
| `cloudtrail:LookupEvents` | **DENIED** | `AccessDeniedException … LookupEvents` |
| `logs:DescribeLogGroups` | **DENIED** | `AccessDeniedException … DescribeLogGroups` |
| `s3:ListAllMyBuckets` | **DENIED** | `AccessDenied … ListBuckets` |
| `backup:ListBackupPlans` | **DENIED** | `AccessDeniedException … ListBackupPlans` |
| `sns:ListTopics` | **DENIED** (non-zero exit) | command failed; message did not match the denial patterns, so treat as unverified |
| `iam:GetUser` / `iam:ListRoles` | **DENIED** | `AccessDenied` |
| `iam:CreateServiceLinkedRole` | **DENIED** | `AccessDenied … CreateServiceLinkedRole` |
| `iam:PutUserPolicy` (self-escalation check) | **DENIED** | `AccessDenied` — this user cannot widen its own permissions |
| `secretsmanager:ListSecrets` | **DENIED** | `AccessDeniedException` |
| `ssm:DescribeParameters` | **DENIED** | `AccessDeniedException` |
| `ec2:DescribeInstances` / `DescribeVpcs` / `DescribeSnapshots` | **ALLOWED** | returned JSON (exit 0) |
| `cloudwatch:DescribeAlarms` | **ALLOWED** | `{"MetricAlarms": [], "CompositeAlarms": [], "LogAlarms": []}` — no alarms exist today |
| `cloudwatch:ListMetrics` | **ALLOWED** | empty for namespace `LXON` — nothing publishes metrics today |

Two conclusions the whole "deploy CloudFormation / enable CloudWatch / CloudTrail / Backup"
bullet list depends on:

1. **CloudFormation, CloudTrail, Backup, Logs, S3, SNS and all of IAM are closed to this
   identity.** Phase 3 cannot be executed by me, by any sequence of commands. It needs a
   grant from someone who can edit this user's policy.
2. **CloudWatch read is already open.** I did not test `PutMetricAlarm` / `PutMetricData`
   because those write to the account and this round was scoped to prepare-and-verify. If
   writes turn out to be allowed too, Phase 6's metrics-and-alerting item needs **no grant
   at all** — that is the first thing to re-probe after this document, and it is the
   cheapest win in the whole list.

## 2. The templates do not currently deploy a validator

All five files parse as CloudFormation YAML after one syntax fix (see 2.1). Their declared
resources touch 13 services: `ec2, cloudformation, iam, cloudwatch, logs, sns, s3,
cloudtrail, backup, kms, codebuild, codedeploy, codepipeline`. But auditing them against
what the running chain needs:

**2.1 `lxon-validator-single.yaml:297-301` was invalid YAML** — the `path` dimension of the
disk alarm was nested inside the `InstanceId` list item instead of starting a new one
(`- Name: path` at the wrong indent). CloudFormation would have rejected the file at upload.
Fixed in this commit; the other four templates parsed on the first try.

**2.2 The security group opens SSH and RPC to the world.** `lxon-validator-multi-az.yaml:232-234`
and `:257-259` allow `22` from `0.0.0.0/0`, and `:262-264` allows `8545` from `0.0.0.0/0`.
That is precisely the chain-takeover vector that was closed on the live node on 2026-10-20:
QBFT here is n=1/f=0, so a world-reachable RPC with the QBFT namespace lets any stranger
POST `qbft_proposeValidatorVote` and become a consensus validator. Deploying this template as
written would rebuild the vulnerability on fresh machines. **Do not deploy until the ingress
is scoped** (SSH to a pinned CIDR, 8545 to the RPC tier or loopback only, `--host-allowlist`
and a trimmed `--rpc-http-api` as in `lxon-evm-node/besu/entrypoint-besu.sh`).

**2.3 No instance installs or runs anything.** `lxon-validator-multi-az.yaml` has no
`UserData` (grep: 0 matches) — the instances do get an instance profile
(`ValidatorInstanceProfile`, `:291` and `IamInstanceProfile` on all three at `:346/:391/:436`)
with `CloudWatchAgentServerPolicy` attached, and their root volumes are `gp3` `Encrypted: true`
(`:352-353`), so the *permissions* for a metrics agent exist. But with no user-data nothing
installs the agent, nothing writes its config, and nothing installs Docker or Besu: the result
is three encrypted, correctly-role'd Ubuntu boxes running no chain software and publishing no
`CWAgent` metrics. The working deployment is `lxon-evm-node/aws/deploy.sh` + `user-data.sh` +
`push-secrets.sh`, which the templates do not reference at all. `infrastructure/README.md`
lists "CloudWatch Agent configuration" as a delivered resource; what is actually delivered is
only the managed-policy attachment, so read that line as unmet.

**2.4 Every AMI id in the mapping is stale or wrong for eu-north-1.** The `RegionMap` reuses
`ami-01e8f3f2f3e9c818a` for us-west-1, us-west-2, eu-north-1 and eu-central-1 — AMI ids are
region-scoped, so that cannot be valid in four regions. Measured:

```
aws ec2 describe-images --region eu-north-1 --image-ids ami-01e8f3f2f3e9c818a
  → InvalidAMIID.NotFound … does not exist
aws ec2 describe-images --region eu-north-1 --image-ids ami-0c7217cdde317cfec
  → InvalidAMIID.NotFound … does not exist
aws ec2 describe-instances --instance-ids i-0be453b2850bd6eae   → ami-0fd9576cca965bd19   (the image the live node actually uses)
```

So a stack deployment would fail at `Validator1Instance` even with full permissions. Use the
live node's AMI, or better an SSM parameter (`/aws/service/canonical/ubuntu/server/24.04/...`)
as `deploy.sh` does.

**2.5 `ValidatorCount` is decorative.** It is declared at `lxon-validator-multi-az.yaml:70`
and referenced **nowhere**; the template hardcodes `Validator1Instance`, `Validator2Instance`,
`Validator3Instance`. Parameterising the validator count needs `Fn::ForEach` in a transform,
or three separate stacks.

**2.6 Nested templates need a bucket.** `lxon-infrastructure-master.yaml:108-111` points
`TemplateURL` at `./lxon-validator-multi-az.yaml`. Relative paths resolve only in the
console; from the CLI the child templates must be uploaded to S3 first, which is why
`CloudFormationTemplateBucket` appears in the policy.

**2.7 The alarms have no metric behind them.** `BlockProductionAlarm` consumes
`Namespace: LXON/Blockchain, MetricName: BlocksProduced` and the single-validator template
consumes `CWAgent` metrics — but no CloudWatch agent is installed (see 2.3) and nothing
publishes `BlocksProduced`. `cloudwatch:DescribeAlarms` currently returns zero alarms and
`ListMetrics` for the `LXON` namespace returns nothing, which confirms it: those alarms would
sit in `INSUFFICIENT_DATA` and alert on nothing. A tiny exporter (read `eth_blockNumber` from
the sealer over loopback, `PutMetricData` every 60 s) is the missing piece and is a
prerequisite for Phase 6, not a follow-up.

## 3. The grant

`lxon-deploy-policy.json` in this directory is the least-privilege shape derived from the 32
resource types the templates declare: `cloudformation` scoped to `stack/lxon-*`, `iam` scoped
to `role/lxon-*` and `instance-profile/lxon-*` (so `PassRole` cannot hand an arbitrary
existing role to a new instance), CloudTrail scoped to `trail/lxon-*`, and an S3 bucket only
for the CFN artifact path. Deliberately absent: `secretsmanager:*`, `ssm:*` (the validator
key is delivered by `push-secrets.sh` and should stay outside any deploy identity), and
`iam:CreateServiceLinkedRole`, which is account-wide, cannot be resource-scoped, and is
required by both AWS Backup and CloudTrail — that one needs an explicit human yes.

To attach it, someone with `iam:PutUserPolicy` runs:

```bash
aws iam put-user-policy \
  --user-name devin-blockchain-deployer \
  --policy-name lxon-cloudformation-deploy \
  --policy-document file://infrastructure/cloudformation/lxon-deploy-policy.json
```

Verify from this identity afterwards (all three must exit 0):

```bash
aws cloudformation validate-template --template-body file://infrastructure/cloudformation/lxon-validator-multi-az.yaml
aws cloudformation list-stacks --region eu-north-1
aws iam get-user
```

## 4. What the grant still does not solve

- **The running chain is not under CloudFormation.** `i-0be453b2850bd6eae`, its EIP
  (`eipalloc-077274a8a2ea43be0`) and `lxon-node-sg` were created by `deploy.sh` with raw CLI
  calls. Deploying the master stack builds a *parallel* estate — a second VPC, a second set of
  instances, a second EIP — and does not make the existing validator highly available. Either
  use `cloudformation:ImportResources` (needs CloudFormation Resource Import, and only
  supports resource types that can be imported), or treat the stack as the new estate and plan
  a migration: the EIP is the RPC address published to wallets, so moving it means re-pointing
  DNS for `rpc.lxon.in` and accepting a window where the chain has no published endpoint.
- **Multi-AZ compute is not multi-validator.** QBFT's validator set is fixed in the genesis at
  block 0 and changed only by votes; with n=1 today, the quorum for a vote is one, and adding
  signers requires restarting the sealer with the QBFT namespace temporarily enabled
  (`BESU_RPC_API` in `lxon-evm-node/besu/entrypoint-besu.sh`) and running three more nodes with
  the *same genesis and different keys*. Three fresh instances from this template would join
  nothing. Two validators with the same genesis and the same key fork the chain — that is the
  standing constraint on this repo, not a preference.
- **Cost is a decision, not a config.** Multi-AZ with 3× t3.medium plus a NAT gateway in
  eu-north-1 is roughly $0.05/hr per instance and $0.055–0.065/hr for NAT plus its data
  charge — call it $150–$200/month for a chain whose measured external traffic is zero
  (the last 240 blocks contain no transactions from anyone else).

## 5. Suggested order, once someone wants to spend

1. Re-probe `cloudwatch:PutMetricAlarm` + `PutMetricData` with this identity (10 minutes, no
   grant needed if it works) → ship the block-production exporter → real alarms exist.
2. Fix the templates' ingress, AMI and user-data (2.2, 2.3, 2.4) — they are not safe to
   deploy as they stand.
3. Ask for the grant in §3, then `ValidateTemplate` and `ListStacks` as the acceptance test.
4. Only then decide import-vs-parallel-estate, because the answer changes what the stack is for.
