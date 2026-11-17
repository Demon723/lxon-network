# Secondary PQ Signatures

## What it is

LXON uses ML-DSA-65 (lattice) as its primary signature scheme. Secondary
signatures (MAYO, multivariate) provide defense-in-depth for high-value
operations. An attacker must break **both** algebraic families.

## Where it's used

| Context | Contract / Module | Flag |
|---------|-------------------|------|
| Validator key registration | `ValidatorKeyRegistry` | `secondary_sig_enabled` |
| High-value wrapper vault | `PQWrappedAssetVault` | `secondary_vault_large` |
| Satellite anchor attestation | `SecondaryAttestor` | `secondary_satellite_attest` |
| Backend admin API | `routes/secondary.ts` | `secondary_backend_routes` |

## Thresholds

| Amount | Requirement |
|--------|-------------|
| < 1,000 LXON | ML-DSA-65 only |
| 1,000 – 100,000 LXON | ML-DSA-65 + MAYO |
| >= 100,000 LXON | ML-DSA-65 + MAYO + 2-of-3 attestors |

## Scheme support

| Scheme | Status | Params |
|--------|--------|--------|
| MAYO-1 | Active (fails closed) | 454 B sig, 1420 B pk |
| MAYO-2 | Active (fails closed) | 216 B sig, 4368 B pk |
| MAYO-3 | Active (fails closed) | 681 B sig, 2986 B pk |
| MAYO-5 | Active (fails closed) | 964 B sig, 5554 B pk |
| SQIsign | Disabled | 177 B sig, 148 B pk |

## Never use for

- Consensus messages
- Transaction signing
- State roots

## Key rotation

Run `pnpm keygen` (via the CLI) to produce BOTH primary and secondary keys.
The CLI prints the registry calldata for both rotations.

## Audit status

⚠️ Not audited. The MAYO verifiers fail closed until real implementations
are wired (Rust: `cargo build --features mayo`; TS: WASM binding).

## References

- NIST Round 3 candidates: `docs/research/pqc-watchlist.md`
- Threat model: `docs/threat-model.md`
