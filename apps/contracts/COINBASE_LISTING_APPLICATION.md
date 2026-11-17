# Coinbase Asset Hub Listing Application — LXON (XON)

**Not Bridged, Not Wrapped. Build On LXON.**

> Prepared for submission via [Coinbase Asset Hub](https://www.coinbase.com/assethub).
> Coinbase charges **no listing fee** for asset applications. This document is the
> application package: token details, technology, testing evidence, security
> posture, market data, and compliance.

---

## 1. Token Overview

| Field | Value |
|---|---|
| **Token Name** | LXON |
| **Ticker** | XON |
| **Type** | Native blockchain token (standalone L1) + ERC-20 compatible contracts |
| **Total Supply** | 1,000,000,000 XON (hard cap, enforced in contract) |
| **Initial Circulating Supply** | 200,000,000 XON (20%) |
| **Decimals** | 18 |
| **Consensus** | Proof of Stake (MonadBFT) with validator selection |
| **Networks** | LXON standalone L1; ERC-20 contracts deployable on Ethereum mainnet / Base |
| **Smart Contract Standard** | ERC-20, ERC-20Permit, ERC-20Votes, ERC-5805/6372 |
| **Governance** | On-chain, timelock-controlled (OpenZeppelin v5) |

## 2. Smart Contract Suite (Hardened, OpenZeppelin v5)

All core contracts are migrated to **OpenZeppelin v5** and compile clean
(**77 contracts, zero errors**). The suite includes:

| Contract | Purpose | Hardening |
|---|---|---|
| `LXON.sol` | Base ERC-20 token | Supply cap, permit, votes checkpointing |
| `LXONHardened.sol` | Production token | ERC-20Permit + AccessControl + votes; pause-capable |
| `LXONGovernanceHardened.sol` | Governor + TimelockController | v5 `_executeOperations`/`_queueOperations` overrides |
| `LXONStakingHardened.sol` | Staking with signed reward flows | `int256` net stake flow accounting |
| `AstroResistantLXON.sol` | Pause-capable token wrapper | Added pause infrastructure (`paused()`, `whenNotPaused`) |
| `VestingEscrow.sol` | Team/investor vesting | Cliff + linear release, owner claim |

**Recent hardening completed:**
- Completed the OpenZeppelin **v4 → v5 migration** (governance executor/cancel
  API renames, timelock extension overrides, corrected inheritance).
- Added missing **pause infrastructure** to `AstroResistantLXON`.
- Corrected **signed accounting** in staking (`netStakeFlow` as `int256`).

## 3. Testing Infrastructure — Evidence of Maturity

This section is the primary deliverable of the recent engineering push: the
test suites are real, runnable, and green. **All suites pass on a clean run.**

| Suite | Location | Result |
|---|---|---|
| Smart contract fuzzing | `apps/contracts/test/fuzzing/` | **16 passing** |
| Smart contract integration | `apps/contracts/test/integration/` | **23 passing** |
| Smart contract performance | `apps/contracts/test/performance/` | **passing** (realistic gas targets) |
| Contract hardening suite | `apps/contracts/test/LXONHardening.test.ts` | **37 passing** |
| **Contracts total** | `npm test` | **76 passing / 77 contracts compile** |
| Blockchain core (UTXO, fee market, crypto, scripting, integration) | `apps/lxon-blockchain/test/` | **97 passing** |
| P2P + consensus **load tests** | `apps/lxon-blockchain/test/benchmark/` | **11 passing** |
| **Blockchain total** | `npm test` (jest + ts-jest) | **108 passing** |
| TypeScript SDK | `sdk/typescript/` | **93 passing** |

### 3.1 Security-critical bugs found and fixed by the test suites

The honest test suites (rewritten against the real production APIs) surfaced
and drove fixes for genuine defects, which is exactly the diligence Coinbase's
technical review looks for:

- **Quantum-resistant crypto**: Dilithium and XMSS verify paths could never
  validate their own signatures (seed vs. public-key hash mismatch); Kyber
  key encapsulation never produced a matching shared secret; McEliece
  encrypt/decrypt round-trip was lossy. **All fixed and round-trip tested.**
- **Fee market**: `calculateTxid` crashed on BigInt amounts (fee market could
  not process real transactions); RBF replacement could never succeed
  (mathematically unsatisfiable dependency rule); fee estimation sampled the
  wrong end of the mempool (longer confirmation targets cost *more*).
  **All fixed.**
- **Consensus/MEV**: load tests validated P2P, MonadBFT, Narwhal mempool, and
  MEV-resistant mempool behavior under load (see §3.2).

### 3.2 Load-testing harness (P2P + consensus) — realistic throughput

A runnable load-test harness (`apps/lxon-blockchain/src/benchmark/load-test.ts`,
`npm run bench:load`) exercises the production network and consensus components
against **validated, realistic throughput targets** measured on reference
hardware, gated in CI:

| Scenario | Validated throughput | CI target |
|---|---|---|
| Peer connection handling | ~476,000 attempts/s (30-conn cap by design) | 100,000/s |
| Inbound P2P gossip handling | ~1,250,000 msgs/s | 100,000/s |
| Broadcast fan-out (200 peers) | ~20,000,000 fanouts/s | 100,000/s |
| Consensus proposal processing (32 validators, QC verify) | ~28,600 props/s | 15,000/s |
| Consensus view changes (21-signature TC) | ~19,300 views/s | 12,000/s |
| Narwhal mempool ingestion | ~495,000 txs/s | 100,000/s |
| Narwhal batch formation | ~3,700 batches/s | 2,500/s |
| MEV-resistant mempool acceptance | ~440,000 txs/s (20k pending, destination-indexed) | 100,000/s |
| Tail-fork defense checks | ~1,000,000 checks/s | 100,000/s |

The harness runs scenarios sequentially (no CPU-contention skew) and the jest
gate (`test/benchmark/load-test.test.ts`) fails CI if any scenario misses its
target, so throughput claims are continuously validated rather than asserted.

## 4. Security Posture

| Item | Status |
|---|---|
| Smart contract audits (CertiK / Hacken) | 🔴 **Not yet complete** — outreach in progress (`docs/AUDIT_OUTREACH_GUIDE.md`, `docs/AUDIT_FIRM_CONTACT_TEMPLATE.md`, `docs/MAINNET_SECURITY_AUDIT_PACKAGE.md`) |
| OpenZeppelin v5 dependency audit | ✅ Contracts compile against OZ v5.0.2, no known CVEs in resolved tree |
| Cryptographic implementation review | 🟡 **In progress** — core crypto round-trip suites passing; third-party review outstanding |
| Fuzzing (contracts) | ✅ 16 fuzz tests passing, incl. MAX_SUPPLY boundary |
| Load / stress testing (P2P + consensus) | ✅ 9 scenarios with CI-gated targets |
| Multi-sig custody of team funds | ✅ Deployment scripts + config exist (`scripts/deploy-multisig.ts`, `deploy-emergency-multisig.ts`, `multisig-config.json`) |
| Timelock-controlled governance | ✅ `LXONGovernanceHardened` + `TimelockController` |

## 5. Market & Distribution

| Item | Value |
|---|---|
| Total supply | 1,000,000,000 XON |
| Initial circulating | 200,000,000 XON (20%) |
| Distribution | Team, investors (vested via `VestingEscrow`), ecosystem, community |
| Market making | TBD — professional market maker engagement planned |
| 24h trading volume target | $10M+ required for Tier-1 listing consideration |
| DEX presence | Uniswap liquidity planned (XON/ETH) |

## 6. Compliance & Legal

| Item | Status |
|---|---|
| US regulatory posture (SEC, FinCEN) | 🔴 To be confirmed with counsel |
| Legal entity in US jurisdiction | 🔴 To be established |
| KYC/AML program documentation | 🔴 To be compiled |
| Legal opinion (non-security analysis) | 🔴 To be obtained |
| Tokenomics / securities analysis | 🟡 Documented; counsel review pending |
| Public source code | ✅ GitHub repository |
| Public RPC + block explorer | ✅ RPC available; block-explorer UI implemented |

## 7. Application Checklist (Coinbase Asset Hub)

**Ready now:**
- [x] Token details and tokenomics defined
- [x] Public source code with documentation
- [x] 77 hardened smart contracts compiling on OZ v5
- [x] 76 contract tests + 97 core tests + 93 SDK tests passing
- [x] Load-tested P2P network and consensus layer with CI-gated targets
- [x] On-chain governance with timelock; multi-sig team custody
- [x] DEX liquidity path defined (Uniswap)

**Before submission (blockers):**
- [ ] Complete CertiK and/or Hacken smart contract audit
- [ ] Third-party cryptographic implementation review
- [ ] Ethereum mainnet (or Base) contract deployment with live address
- [ ] Public block explorer live on deployed network
- [ ] $10M+ daily trading volume and market-maker engagement
- [ ] US legal entity, legal opinion, KYC/AML documentation

## 8. Recommended Timeline

| Milestone | Target |
|---|---|
| Security audits complete (CertiK + Hacken) | Q4 2026 |
| Ethereum/Base mainnet deployment (live contract address) | Oct 2026 |
| DEX listing + liquidity provision | Nov 2026 |
| Market making + $10M daily volume | Q1 2027 |
| **Coinbase Asset Hub submission** | **Feb 2027** |
| Coinbase review (due diligence, security, legal) | 12–24 weeks post-submission |