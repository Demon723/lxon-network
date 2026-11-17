# IAM role for driving this kit remotely

Two documents, both generated from what the scripts actually call rather than from a managed
policy, plus a checker that proves the coverage.

| file | what it is |
|---|---|
| `lxon-deployer-trust.json` | who may assume the role |
| `lxon-deployer-policy.json` | what the role may do |
| `check-policy-coverage.py` | evaluates the policy against deploy.sh's real requests — 20 positive, 15 negative cases, all passing |

**The node itself needs no role at all.** Measured, not assumed: `user-data.sh` contains no `aws`
invocation and no IMDS lookup, and `deploy.sh`'s `run-instances` passes no `--iam-instance-profile`.
The sealer only ever talks to Besu and Docker. So there is no instance profile to create, and a
compromised node cannot call AWS — which is the point of keeping RPC loopback-only.

## How the action list was derived

Every `aws <service> <op>` in `preflight.sh`, `deploy.sh`, `verify.sh`,
`NewSealerKeyOnInstance.sh`, `BackupSealerKeySecurely.sh` and `../aws/push-secrets.sh`, with line
continuations joined, then hyphenated CLI names mapped to IAM action names. One case is not a
literal in the source: `aws ec2 wait instance-running` is a waiter, and what it actually calls is
`ec2:DescribeInstanceStatus`, so that action is in the policy. `create-security-group` takes no
`--vpc-id`, so `DescribeVpcs` is deliberately absent.

## Why the shape is what it is

`ec2:CreateTags` is in its **own** statement. It was bundled with `RunInstances`, which requires
`ec2:InstanceType`, `ec2:Encrypted` and `ec2:MetadataHttpTokens` — condition keys that do not
exist in a `CreateTags` request on an EIP allocation. An absent key fails `StringEquals`, so the
bundled version would have denied `deploy.sh:123` and broken the deploy on a role that parsed
fine. The checker prints that presence table every run so the mistake cannot silently return.

Cleanup permissions are included on purpose. A role that can launch but not terminate leaves an
instance billing after you stop wanting it, and the free plan closes the account in six months
anyway — so refusing to stop spend is not caution.

`TerminateInstances` is scoped to instances tagged `Project=lxon`. That is only safe because
`RunInstances` requires `aws:RequestTag/Project=lxon`, i.e. every instance this role can create is
one it can later remove — and nothing it cannot identify.

The explicit `Deny` on non-`t4g.micro/small` is the credit guard. On the credit plan the budget is
credits, not a 750-hour allowance, so the binding constraint is instance size.

## Create it

**Chicken-and-egg, so read this first:** creating a role needs an identity that can already call
`iam:CreateRole`. This machine has no valid credentials at all, so use the console.

AWS Console on account `044409363656` → IAM → Roles → Create role → *Trusted entity: AWS account* →
*this account* → paste `lxon-deployer-trust.json` as the advanced/JSON trust editor → next →
Create inline policy → paste `lxon-deployer-policy.json` → name it `lxon-deployer` → create role
`lxon-deployer`.

If you end up with admin credentials instead, the CLI route is:

```bash
aws iam create-role --role-name lxon-deployer \
  --assume-role-policy-document file://lxon-deployer-trust.json
aws iam put-role-policy --role-name lxon-deployer \
  --policy-name lxon-deployer --policy-document file://lxon-deployer-policy.json
```

## Use it

Give your console/IAM identity `sts:AssumeRole` on `arn:aws:iam::044409363656:role/lxon-deployer`.
The trust policy authorising the account is necessary but not sufficient — a user with no attached
policies still cannot assume it.

`aws login` gives credentials for the console identity, not the role, so chain them:

```bash
aws login --profile lxon-console
aws configure set role_name   lxon-deployer --profile lxon-deployer
aws configure set source_profile lxon-console --profile lxon-deployer
aws configure set region      eu-north-1   --profile lxon-deployer
AWS_PROFILE=lxon-deployer ./preflight.sh   # must report Account 044409363656
```

## Two things that will bite you

**`INSTANCE_TYPE=t4g.medium` is refused by design.** If 1 GiB proves too tight for Besu + JVM and
you want to override the type, the policy blocks it, and the failure is an `UnauthorizedOperation`
from IAM rather than a message from the script. Either launch `t4g.small` (2 GiB, allowed, and what
`README.md` suggests as the fallback), or edit both the `StringEquals` allow list and the
`StringNotEquals` deny list — missing the Deny is the one edit that leaves you with a confusing
error, because an explicit Deny always wins.

**No MFA is required.** An earlier draft gated the trust policy on `aws:MultiFactorAuthPresent`.
That key is absent for plain access keys, so if MFA is not enrolled every assume is denied — a lockout
shaped like a good security decision. If the account does have MFA, the stricter trust is:

```json
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"AWS":"arn:aws:iam::044409363656:root"},
  "Action":["sts:AssumeRole","sts:TagSession"],
  "Condition":{"Bool":{"aws:MultiFactorAuthPresent":"true"}}}]}
```

To tighten *who* rather than *how*, replace the `root` principal with the specific user ARN. Do not
leave a placeholder like `<your-username>` in the live document — a non-matching ARN denies silently.

## Unverified

Nothing here has been submitted to AWS. IAM accepts a policy this checker approves and can still
refuse a call for reasons outside the document (an SCP, a permissions boundary, the account still
being in free-tier setup). Treat `python3 check-policy-coverage.py` as proof of internal
consistency, and `preflight.sh` as the first real test against AWS.
