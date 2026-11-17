#!/usr/bin/env python3
"""
Runs ON THE INSTANCE. Generates a fresh secp256k1 node/validator key and writes it to the
Besu key file. Prints the PUBLIC POINT only -- the private scalar is never written to stdout,
never scp'd, never carried over the wire.

Usage (remote):  python3 remote_genkey.py /opt/lxon/besu/privatekey.txt
Exit 1 if the target already holds a key: rotating a live sealer is a genesis change, not a
file overwrite, so that case has to be a deliberate act.
"""
import os, re, subprocess, sys

if len(sys.argv) != 2:
    print('usage: remote_genkey.py <path-to-besu-keyfile>', file=sys.stderr)
    sys.exit(2)

target = sys.argv[1]
if os.path.exists(target) and os.path.getsize(target) > 0:
    print('ERROR: %s already contains a key (%d bytes). Refusing to overwrite a live consensus '
          'identity: this chain takes its validator from genesis extraData, so replacing the key '
          'means rebuilding genesis and restarting the chain.' % (target, os.path.getsize(target)),
          file=sys.stderr)
    sys.exit(1)

d = '/tmp/lxon-keygen'
os.makedirs(d, mode=0o700, exist_ok=True)
pem = os.path.join(d, 'k.pem')

# openssl's own CSPRNG generates the key; the PEM never leaves /tmp and is shredded below.
subprocess.run(['openssl', 'ecparam', '-name', 'secp256k1', '-genkey', '-noout', '-out', pem],
               check=True)

der = subprocess.run(['openssl', 'ec', '-in', pem, '-outform', 'DER'],
                     capture_output=True, check=True).stdout
i = der.find(bytes.fromhex('0420'))          # OCTET STRING wrapping the 32-byte scalar
if i < 0 or len(der) < i + 34:
    print('ERROR: could not locate the private scalar in the DER', file=sys.stderr)
    sys.exit(1)
scalar = der[i + 2:i + 34]
if len(scalar) != 32:
    print('ERROR: expected a 32-byte scalar, got %d' % len(scalar), file=sys.stderr)
    sys.exit(1)

pubder = subprocess.run(['openssl', 'ec', '-in', pem, '-pubout', '-outform', 'DER'],
                        capture_output=True, check=True).stdout
point = pubder[-65:]
if point[0] != 0x04 or len(point) != 65:
    print('ERROR: unexpected public point encoding', file=sys.stderr)
    sys.exit(1)

# Besu's --node-private-key-file format, matching the file this project already runs:
# 64 lowercase hex chars, no 0x, one trailing newline, mode 0600.
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as fh:
    fh.write(scalar.hex() + '\n')

def wipe(path):
    """Overwrite then unlink. `shred -u` is used where it exists (Ubuntu); the python fallback is
    what actually protects the PEM on hosts without coreutils shred -- leaving a plaintext key
    file in /tmp is the failure mode this whole ceremony is meant to avoid."""
    try:
        r = subprocess.run(['shred', '-u', '-z', path], check=False)
    except FileNotFoundError:
        r = None
    if os.path.exists(path):
        n = os.path.getsize(path)
        with open(path, 'r+b') as fh:
            fh.write(b'\0' * n)
            fh.flush()
            os.fsync(fh.fileno())
        os.unlink(path)
    return not os.path.exists(path)


wipe(pem)
try:
    os.rmdir(d)
except OSError:
    pass

print('KEYFILE_WRITTEN   %s (%d bytes, mode %s)' % (target, os.path.getsize(target),
                                                    oct(os.stat(target).st_mode & 0o777)))
print('VALIDATOR_PUBPOINT ' + point[1:].hex())      # public: safe to print, safe to scp back
