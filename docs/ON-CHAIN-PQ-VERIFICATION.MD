# On-Chain PQ Verification

## Why it matters

V1 of `SatelliteSignature` used M-of-N attestors because Solidity had no
way to verify ML-DSA. V2 removes that trust assumption: the contract
verifies the satellite's ML-DSA-65 signature directly.

## Two implementations

| Implementation | When used | Gas cost |
|---------------|-----------|----------|
| `MlDsaVerifierPrecompile` | Chain supports EIP-8051 | ~50k gas |
| `MlDsaVerifierPure` | Fallback (any EVM) | ~4.9M–8.1M gas |

The factory probes the precompile at deploy time and picks automatically.

## EIP-8051

[EIP-8051](https://eips.ethereum.org/EIPS/eip-8051) adds two precompiles:
- `VERIFY_MLDSA` — NIST FIPS-204 compliant
- `VERIFY_MLDSA_ETH` — Keccak-based, cheaper

LXON should target EIP-8051 adoption. Until it's standardized, the pure
Solidity fallback keeps the chain functional.

## Pure Solidity verifier

Based on [ZKNoxHQ/ETHDILITHIUM](https://github.com/ZKNoxHQ/ETHDILITHIUM).
The audited NTT + polynomial arithmetic is ~2000 lines. Our scaffold
fails closed (returns `false`) until that's integrated.

**Action item**: vendor the ETHDILITHIUM verifier into
`apps/contracts/contracts/satellite/pq/` and replace `_verifyInternal`.

## Gas budget

At 4.9M gas per anchor and 30M gas/block, a block fits ~6 anchors. The
gateway batches multiple satellite telemetry packets per anchor tx to
amortize cost.

## Security considerations

- **Rejection sampling variance**: ML-DSA signing has variable cost due
  to rejection sampling. Our canonical message includes `seq` and
  `emittedAt`, so a re-signed packet produces a different anchorId.
- **Key rotation**: `registerSatellite` is governance-only. Rotating a
  satellite key requires a governance proposal.
- **Replay protection**: `highestSeq` monotonically increases per satellite.
