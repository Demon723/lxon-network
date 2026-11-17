#!/usr/bin/env python3
"""
Generate ECDSA keypair for verification service
Simple version using built-in libraries
"""

import hashlib
import secrets

# Generate private key (32 bytes)
private_key_bytes = secrets.token_bytes(32)
private_key_hex = private_key_bytes.hex()

# Derive public key from private key (simplified for demo)
# In production, use proper EC library like cryptography
# For now, we'll use a placeholder derivation
public_key_bytes = hashlib.sha256(private_key_bytes).digest()
public_key_hex = public_key_bytes.hex()

# Derive Ethereum address (last 20 bytes of keccak256 hash of public key)
keccak256 = hashlib.sha3_256(public_key_bytes).hexdigest()
address = "0x" + keccak256[-40:]

print("=" * 60)
print("ECDSA Keypair for Verification Service (Demo)")
print("=" * 60)
print(f"\nPrivate Key (hex): {private_key_hex}")
print(f"\nPublic Key (hex): {public_key_hex}")
print(f"\nEthereum Address: {address}")
print("\n" + "=" * 60)
print("SECURITY WARNING: Keep the private key secure!")
print("This is a demo key - use proper EC library in production!")
print("=" * 60)

# Save to files
with open('verification_service_private_key.hex', 'w') as f:
    f.write(private_key_hex)

with open('verification_service_public_key.hex', 'w') as f:
    f.write(public_key_hex)

with open('verification_service_address.txt', 'w') as f:
    f.write(address)

print("\nKeys saved to:")
print("- verification_service_private_key.hex")
print("- verification_service_public_key.hex")
print("- verification_service_address.txt")
