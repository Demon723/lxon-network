#!/usr/bin/env python3
"""Generate the chain-724 Phase 2 deployer key ON THE INSTANCE and return it only in encrypted form.

Nothing here computes an address or a keccak digest, and that is deliberate. A geth-v3 keystore needs
keccak-256 for its `mac` field and for the address; the first draft of this file implemented keccak in
pure python, and it failed three known-answer vectors (a transposed rho-offset table, then a chi step
that complemented a whole lane list instead of a lane). A subtly wrong keccak does not crash -- it
produces a well-formed keystore whose address points somewhere nobody owns, and the funding transfer
would still "succeed". So the digest work belongs on the operator's machine, on @noble/hashes: the same
implementation the CREATE-address collision checker validated by reproducing four real 724 contract
addresses. The wrapper then requires two INDEPENDENT derivations to agree -- @noble's, and foundry's when
it decrypts the keystore -- and refuses if they do not.

What crosses back: scrypt parameters and salt, the AES-128-CTR IV, the ciphertext, and the public point.
Not the private scalar, which is generated, encrypted and dropped inside one process. The password enters
over stdin, never argv -- argv is world-readable in `ps`.

    usage (remote):  python3 remote_gen724deployer.py        # password on STDIN
                     prints one line:  KEYJSON {...}
"""
import json
import secrets
import sys

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

N, R, P, DKLEN = 2 ** 18, 8, 1, 32


def main():
    password = sys.stdin.buffer.read().rstrip(b"\n")
    if len(password) < 16:
        print("REFUSE: the password on stdin is shorter than 16 bytes", file=sys.stderr)
        return 4

    key = ec.generate_private_key(ec.SECP256K1())
    priv = key.private_numbers().private_value.to_bytes(32, "big")
    fmt = getattr(PublicFormat, "UncompressedPoint", None) or getattr(PublicFormat, "Uncompressed")
    pub = key.public_key().public_bytes(Encoding.X962, fmt)

    salt = secrets.token_bytes(32)
    iv = secrets.token_bytes(16)
    dk = Scrypt(salt=salt, length=DKLEN, n=N, r=R, p=P).derive(password)
    enc = Cipher(algorithms.AES(dk[:16]), modes.CTR(iv)).encryptor()
    ct = enc.update(priv) + enc.finalize()
    # No MAC sub-key is sent: the operator holds the password and the salt, and derives dk themselves.
    # What must never travel is the scalar, and it never leaves this process.
    del priv, dk, password

    print("KEYJSON " + json.dumps({
        "cipher": "aes-128-ctr", "iv": iv.hex(), "ciphertext": ct.hex(),
        "kdf": "scrypt", "salt": salt.hex(), "n": N, "r": R, "p": P, "dklen": DKLEN,
        "pubkey": pub.hex(), "entropy_source": "instance:secrets+cryptography"}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
