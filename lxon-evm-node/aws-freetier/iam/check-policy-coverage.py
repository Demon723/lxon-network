#!/usr/bin/env python3
"""
Evaluate iam/lxon-deployer-policy.json against the requests aws-freetier/deploy.sh actually
makes, with IAM's real condition semantics.

Why this exists and is not a nicety: a condition key that is ABSENT from the request makes
StringEquals fail, so bundling `ec2:InstanceType` or `ec2:Encrypted` with `ec2:CreateTags` in
one statement denies the EIP tagging at deploy.sh:123 -- the role would look correct, parse
correctly, and then break the deploy it was written for. A coverage check that only compares
action NAMES cannot see that. It also checks the negatives, because an Allow list that never
refuses anything is not a guard.

Explicit Deny always wins. A statement only applies if every condition key it names is present
in the request and matches.
"""
import json, sys, os, fnmatch

HERE = os.path.dirname(os.path.abspath(__file__))
POLICY = json.load(open(os.path.join(HERE, 'lxon-deployer-policy.json')))


def resource_matches(stmt_resource, request):
    if stmt_resource == '*':
        return True
    # IAM globs '*' across the WHOLE resource string, so 'instance/*' matches
    # 'instance/i-0123...'. Splitting on ':' and only honouring a segment that is exactly '*'
    # silently refused every instance-scoped statement -- which read as a policy defect when the
    # policy was right.
    return fnmatch.fnmatchcase(request['arn'], stmt_resource)


def action_matches(stmt_actions, action):
    return any(a == action or a.endswith(':*') and action.startswith(a.rsplit(':', 1)[0] + ':')
               for a in stmt_actions)


def cond_holds(cond, ctx):
    """All operators ANDed; all keys ANDed; a list of values for a key is ORed."""
    for op, pairs in cond.items():
        for key, allowed in pairs.items():
            allowed = allowed if isinstance(allowed, list) else [allowed]
            present = key in ctx
            if op == 'StringEquals':
                if not present or ctx[key] not in allowed:
                    return False
            elif op == 'StringNotEquals':
                # Absent key counts as "not equal" -> condition holds. Fail-safe for Deny.
                if present and ctx[key] in allowed:
                    return False
            elif op in ('Bool',):
                if not present or str(ctx[key]).lower() != str(allowed).lower():
                    return False
            else:
                raise SystemExit(f'evaluator does not implement {op}; refusing to guess')
    return True


def evaluate(action, ctx, arn=None):
    # EC2 reports the real resource ARN to IAM. Using a ':*' placeholder made the
    # instance-scoped TerminateInstances statement fail segment matching and looked like a
    # policy bug when it was not. Give each action the ARN AWS would actually see.
    if arn is None:
        arn = {
            'ec2:TerminateInstances': f'arn:aws:ec2:{R}:044409363656:instance/i-0123456789abcdef0',
            'ec2:RunInstances':        f'arn:aws:ec2:{R}:044409363656:instance/i-0123456789abcdef0',
        }.get(action, f'arn:aws:ec2:{R}:044409363656:*')
    request = {'arn': arn}
    explicit_deny, allowed_by = False, []
    for s in POLICY['Statement']:
        acts = s['Action']
        acts = [acts] if isinstance(acts, str) else acts
        if not action_matches(acts, action):
            continue
        if not resource_matches(s.get('Resource', '*'), request):
            continue
        if s.get('Condition') and not cond_holds(s['Condition'], ctx):
            continue
        if s['Effect'] == 'Deny':
            explicit_deny = True
        else:
            allowed_by.append(s['Sid'])
    if explicit_deny:
        return 'DENY(explicit)', []
    if allowed_by:
        return 'ALLOW', allowed_by
    return 'DENY(implicit)', []


R = 'eu-north-1'
RUN_OK = {'aws:RequestedRegion': R, 'ec2:Region': R, 'ec2:InstanceType': 't4g.micro',
          'ec2:Encrypted': 'true', 'ec2:MetadataHttpTokens': 'required',
          'aws:RequestTag/Project': 'lxon'}
TAG_EIP = {'aws:RequestedRegion': R, 'aws:RequestTag/Project': 'lxon'}
DESCRIBE = {'aws:RequestedRegion': R}
TERM_OK = {'aws:RequestedRegion': R, 'ec2:ResourceTag/Project': 'lxon'}

# --- every call deploy.sh / preflight.sh / verify.sh / push-secrets.sh makes --------------
CASES = [
    # (action, context, expect_allow, why)
    ('sts:GetCallerIdentity', {}, True, 'account gate at deploy.sh:33'),
    ('ec2:DescribeInstanceTypes', DESCRIBE, True, 'preflight free-tier sizing'),
    ('ec2:DescribeImages', DESCRIBE, True, 'arm64 Ubuntu AMI lookup'),
    ('ec2:DescribeInstances', DESCRIBE, True, 'idempotence + verify'),
    ('ec2:DescribeAddresses', DESCRIBE, True, 'EIP lookup by tag'),
    ('ec2:DescribeKeyPairs', DESCRIBE, True, 'key reuse check'),
    ('ec2:DescribeSecurityGroups', DESCRIBE, True, 'SG reuse check'),
    ('ec2:DescribeInstanceStatus', DESCRIBE, True, '`aws ec2 wait instance-running`'),
    ('ec2:CreateKeyPair', DESCRIBE, True, 'creates ~/.ssh/lxon-eu-north-1.pem'),
    ('ec2:CreateSecurityGroup', DESCRIBE, True, 'lxon-node-sg'),
    ('ec2:AuthorizeSecurityGroupIngress', DESCRIBE, True, '22 + 30303 rules'),
    ('ec2:AllocateAddress', DESCRIBE, True, 'EIP so rpc.lxon.in can repoint'),
    ('ec2:RunInstances', RUN_OK, True, 'the t4g.micro sealer'),
    ('ec2:CreateTags', TAG_EIP, True, 'tags the EIP allocation Name=lxon-node-eip'),
    ('ec2:AssociateAddress', DESCRIBE, True, 'bind EIP to the instance'),
    # --- cleanup: without these the instance bills after you stop wanting it --------------
    ('ec2:TerminateInstances', TERM_OK, True, 'stop billing, lxon-tagged only'),
    ('ec2:DisassociateAddress', DESCRIBE, True, 'release EIP before abandoning it'),
    ('ec2:ReleaseAddress', DESCRIBE, True, 'stop the $0.005/h IPv4 charge'),
    ('ec2:DeleteSecurityGroup', DESCRIBE, True, 'teardown'),
    ('ec2:DeleteKeyPair', DESCRIBE, True, 'teardown'),
]

# --- negatives: a guard that never refuses is decoration ----------------------------------
NEGATIVES = [
    ('ec2:RunInstances', {**RUN_OK, 'ec2:InstanceType': 't4g.medium'},
     'a bigger box than the credit plan survives'),
    ('ec2:RunInstances', {**RUN_OK, 'ec2:InstanceType': 'm5.24xlarge'},
     'the classic runaway-billing shape'),
    ('ec2:RunInstances', {k: v for k, v in RUN_OK.items() if k != 'ec2:InstanceType'},
     'launch template path, instance type unknown to IAM'),
    ('ec2:RunInstances', {**RUN_OK, 'ec2:Encrypted': 'false'},
     'unencrypted root volume'),
    ('ec2:RunInstances', {**RUN_OK, 'ec2:MetadataHttpTokens': 'optional'},
     'IMDSv1, which lets SSRF steal the instance role'),
    ('ec2:RunInstances', {**RUN_OK, 'ec2:Region': 'us-east-1', 'aws:RequestedRegion': 'us-east-1'},
     'outside the one region this kit targets'),
    ('ec2:RunInstances', {k: v for k, v in RUN_OK.items() if k != 'aws:RequestTag/Project'},
     'untagged instance, which cleanup could not find'),
    ('ec2:CreateTags', {k: v for k, v in TAG_EIP.items() if k != 'aws:RequestTag/Project'},
     'tagging resources that are not lxon'),
    ('ec2:TerminateInstances', {k: v for k, v in TERM_OK.items() if k != 'ec2:ResourceTag/Project'},
     'terminating someone else\'s instance'),
    ('iam:CreateRole', {}, 'privilege escalation'),
    ('iam:AttachRolePolicy', {}, 'privilege escalation'),
    ('organizations:CreateAccount', {}, 'leaving the free-tier account boundary'),
    ('ec2:AuthorizeSecurityGroupIngress', {**DESCRIBE, 'aws:RequestedRegion': 'us-east-1'},
     'opening a hole in another region'),
    # Resource ARN must also match: the statement pins region + account, so a correctly tagged
    # instance somewhere else is still refused.
    ('ec2:TerminateInstances', TERM_OK,
     f'a correctly tagged instance in another region',
     'arn:aws:ec2:us-east-1:044409363656:instance/i-0123456789abcdef0'),
    ('ec2:TerminateInstances', TERM_OK,
     f'a tagged instance in a DIFFERENT account (confused deputy)',
     'arn:aws:ec2:eu-north-1:999999999999:instance/i-0123456789abcdef0'),
]

# The statement that bundles CreateTags with RunInstances-only keys is the bug this file exists
# to catch. Show it explicitly: a CreateTags request has no ec2:InstanceType in its context.
ctx_probe = dict(TAG_EIP)
print('Condition-key presence check on a real CreateTags request:')
for k in ('ec2:InstanceType', 'ec2:Encrypted', 'ec2:MetadataHttpTokens', 'ec2:Region'):
    print(f'   {k:28} present={k in ctx_probe}  -> an Allow naming it would DENY this call')
print()

fails = 0
print('POSITIVE -- what deploy.sh must be able to do')
for action, ctx, expect, why in CASES:
    verdict, sids = evaluate(action, ctx)
    ok = verdict == 'ALLOW'
    fails += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {action:38} {verdict:16} {', '.join(sids) or why}")

print('\nNEGATIVE -- what must be refused')
for row in NEGATIVES:
    action, ctx, why = row[0], row[1], row[2]
    arn = row[3] if len(row) > 3 else None
    verdict, sids = evaluate(action, ctx, arn)
    ok = verdict.startswith('DENY')
    fails += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {action:38} {verdict:16} {why}")

npos, nneg = len(CASES), len(NEGATIVES)
print(f"\n{'ALL CASES PASS' if not fails else f'{fails} CASE(S) WRONG'} "
      f"({npos} positive, {nneg} negative)")
sys.exit(1 if fails else 0)
