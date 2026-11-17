#!/usr/bin/env node
// Derive an Ethereum address from a 64-byte secp256k1 public point (X||Y, no 04 prefix).
// Input: 128 hex chars on stdin or as argv[2]. Output: the address only.
//
// This exists so the sealer key ceremony can bring back the PUBLIC point from the instance and
// compute the validator address here. The private scalar is never read off the instance.
//
// Validated 2026-11-02 against `cast wallet address --private-key` on throwaway keys: identical
// address from both paths (0xbe92a7a172e86842fe518e0d37db8db18c0eef7e on the last run).
const { keccak_256 } = require(process.env.NOBLE_SHA3
  || '/Users/adikamble/LXON/LXON/apps/frontend/node_modules/@noble/hashes/sha3.js');
const fs = require('fs');

let hex = (process.argv[2] || fs.readFileSync(0, 'utf8')).trim().replace(/^0x/, '');
if (hex.startsWith('04')) hex = hex.slice(2);          // tolerate the uncompressed marker
if (!/^[0-9a-fA-F]{128}$/.test(hex)) {
  console.error('ERROR: expected 64-byte public point (128 hex chars), got ' + hex.length + ' chars');
  process.exit(2);
}
const dig = keccak_256(Buffer.from(hex, 'hex'));
console.log('0x' + Buffer.from(dig).subarray(-20).toString('hex'));
