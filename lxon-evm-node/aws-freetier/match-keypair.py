#!/usr/bin/env python3
"""
Which local private key, if any, unlocks which EC2 key pair?

Uses AWS's `--include-public-key` and compares the OpenSSH wire form of each local key's public
half. Deliberately NOT a fingerprint comparison: an earlier check hashed SubjectPublicKeyInfo DER
and compared it to EC2's KeyFingerprint, and the two simply are not the same encoding -- it
reported a mismatch for a key pair AWS had generated both halves of. Exact public-key equality has
no such ambiguity.

Prints verdicts only. No key material is written to stdout beyond a 12-character public-half prefix
(public keys are public, and it is the only way to show the reader which key is which).
"""
import subprocess, sys, os, glob

PROFILE = os.environ.get("AWS_PROFILE", "lxon-remote")

LOCAL_KEYS = sorted(
    set(glob.glob(os.path.expanduser("~/.ssh/lxon-*.pem*")) +
        glob.glob(os.path.expanduser("~/.aws/lxon-*.pem")))
)


def sh(cmd):
    # Direct argv, no shell: the paths here come from a glob of $HOME, and shell=True would
    # reparsed them (flagged by review). No shell features are needed.
    return subprocess.run(cmd, capture_output=True, text=True)


def aws_public(region, keyname):
    r = sh(["aws", "ec2", "describe-key-pairs", "--profile", PROFILE, "--region", region,
            "--key-names", keyname, "--include-public-key",
            "--query", "KeyPairs[0].PublicKey", "--output", "text"])
    if r.returncode != 0:
        return None, r.stderr.strip().splitlines()[0] if r.stderr else "no output"
    return r.stdout.strip(), None


def local_public(path):
    r = sh(["ssh-keygen", "-y", "-f", path])
    if r.returncode != 0:
        return None
    parts = r.stdout.strip().split()
    return " ".join(parts[:2]) if len(parts) >= 2 else None


def norm(s):
    if not s:
        return None
    p = s.split()
    return " ".join(p[:2]) if len(p) >= 2 else None


print(f"local private keys found: {len(LOCAL_KEYS)}")
for k in LOCAL_KEYS:
    print("   ", os.path.basename(k))

PAIRS = [("eu-north-1", "lxon-eu-north-1"), ("us-east-1", "lxon-blockchain-key")]

for region, keyname in PAIRS:
    awspub, err = aws_public(region, keyname)
    print(f"\n=== key pair {keyname} in {region} ===")
    if not awspub:
        print(f"  cannot fetch public key from AWS: {err}")
        continue
    print(f"  AWS public half: {norm(awspub)[:12]}…")
    matched = []
    for path in LOCAL_KEYS:
        lp = norm(local_public(path))
        name = os.path.basename(path)
        if lp is None:
            print(f"  {'':11} {name}: not a readable private key")
            continue
        if lp == norm(awspub):
            print(f"  MATCH       {name}")
            matched.append(name)
        else:
            print(f"  no match    {name}")
    if not matched:
        print(f"  >>> NO local private key unlocks instances launched with {keyname}")
