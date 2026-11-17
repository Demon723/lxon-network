#!/usr/bin/env tsx
/**
 * Validator key rotation — produces BOTH primary (ML-DSA-65) and
 * secondary (MAYO) key pairs and prints the registry calldata.
 *
 * Note: MAYO functionality is disabled until WASM/Rust bindings are built.
 */
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { keccak_256 } from '@noble/hashes/sha3';
import { hybridGenerateKeyPair, encodeKey } from '../src/crypto';

const idx = Number(process.argv[2] ?? '0');
const registry = process.argv[3] ?? '0x0000000000000000000000000000000000000000';
const outDir = process.env.KEYGEN_OUT ?? 'chain/validators';

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0); out.set(b, a.length);
  return out;
}

async function main() {
  mkdirSync(outDir, { recursive: true });

  // 1. Primary: ML-DSA-65 + Ed25519 hybrid
  const primary = hybridGenerateKeyPair();
  const primaryPubHash = keccak_256(concat(primary.classicalPublicKey, primary.pqPublicKey));

  // 2. Secondary: MAYO-1 (disabled until WASM/Rust bindings are built)
  let secondaryPubHash = new Uint8Array(32); // zero until keygen works
  let secondaryPubKeyB64: string | null = null;

  console.warn('⚠️  MAYO keygen unavailable — writing primary only.');
  console.warn('    Install the WASM binding or use the Rust CLI for MAYO.');
  console.warn('    Secondary signature support is disabled until bindings are built.');

  // 3. Write key files
  const keyFile = {
    index: idx,
    primary: {
      algorithm: primary.algorithm,
      classicalPublicKey: encodeKey(primary.classicalPublicKey),
      pqPublicKey: encodeKey(primary.pqPublicKey),
      classicalSecretKey: encodeKey(primary.classicalSecretKey),
      pqSecretKey: encodeKey(primary.pqSecretKey),
      pubKeyHash: '0x' + Buffer.from(primaryPubHash).toString('hex'),
    },
    secondary: null, // Disabled until MAYO bindings are built
  };

  const path = join(outDir, `validator-${idx}-rotated-${Date.now()}.json`);
  writeFileSync(path, JSON.stringify(keyFile, null, 2));

  // 4. Print registry calldata
  console.log('\n=== Registry commands ===');
  console.log(`Registry: ${registry}`);
  console.log('');
  console.log('Primary rotation:');
  console.log(`  proposeRotation(bytes32 ${keyFile.primary.pubKeyHash})`);
  console.log(`  acceptRotation()`);
  console.log('');
  console.log('Secondary rotation: DISABLED (MAYO bindings not yet built)');
  console.log('');
  console.log(`Keys written to: ${path}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
