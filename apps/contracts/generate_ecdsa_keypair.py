#!/usr/bin/env python3
"""
Generate ECDSA keypair for verification service
Simple version without web3 dependency
"""

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import hashlib

# Generate ECDSA keypair (secp256k1)
private_key = ec.generate_private_key(ec.SECP256K1(), default_backend())
public_key = private_key.public_key()

# Serialize private key
private_key_bytes = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
)

# Serialize public key (uncompressed)
public_key_bytes = public_key.public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo
)

# Get uncompressed public key for address derivation
public_key_uncompressed = public_key.public_bytes(
    encoding=serialization.Encoding.X962,
    format=serialization.PublicFormat.UncompressedPoint
)

# Remove first byte (0x04 prefix)
public_key_bytes_eth = public_key_uncompressed[1:]

# Hash with keccak256
import sha3
hash_obj = sha3.keccak_256(public_key_bytes_eth)
address_hash = hash_obj.hexdigest()
address = "0x" + address_hash[-40:]

print("=" * 60)
print("ECDSA Keypair for Verification Service")
print("=" * 60)
print(f"\nPrivate Key (PEM):\n{private_key_bytes.decode()}")
print(f"\nPublic Key (PEM):\n{public_key_bytes.decode()}")
print(f"\nEthereum Address: {address}")
print("\n" + "=" * 60)
print("SECURITY WARNING: Keep the private key secure!")
print("Store it in a secure location (e.g., AWS KMS, HashiCorp Vault)")
print("=" * 60)

# Save to files
with open('verification_service_private_key.pem', 'wb') as f:
    f.write(private_key_bytes)

with open('verification_service_public_key.pem', 'wb') as f:
    f.write(public_key_bytes)

with open('verification_service_address.txt', 'w') as f:
    f.write(address)

print("\nKeys saved to:")
print("- verification_service_private_key.pem")
print("- verification_service_public_key.pem")
print("- verification_service_address.txt")
