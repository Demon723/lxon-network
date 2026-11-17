# LXON PQC v2 ("Helios-Q") — Design

<!-- lxon-branch-path-notice:begin -->
> **Paths this document cites that are not on `main`.** Every `apps/contracts/script/v41/…` and
> `apps/attestor/…` path lives on branch **`attested-bridge`** (worktree
> `/Users/adikamble/LXON/attested-bridge-wt`) — 46 and 16 tracked files there, **both directories absent
> from `main`** — so a command copied from this document fails until it is run in that worktree.
> Measured 2026-11-12 and re-measured by `bash docs/tools/check-v41-citations.sh`; the citation rule is
> [`v41-citation-form-2026-11-12.md`](../runbooks/v41-citation-form-2026-11-12.md).
<!-- lxon-branch-path-notice:end -->

Version: v0.3 (supersedes v0.2, which superseded v0.1)
Status: DRAFT, awaiting owner decisions (§7)
Date: 2026-11-03

**Changelog v0.2 → v0.3 — corrections only, no design change.** Deep research (companion doc: [`pqc-size-and-evm-gas-research.md`](./pqc-size-and-evm-gas-research.md)) refuted four factual claims in v0.2. Each is corrected inline in a labelled blockquote so the original claim and its correction are both visible:

1. **§0** — "666 bytes is the smallest signature any NIST-track PQC scheme produces" is **wrong**. SQIsign-L1 (NIST Round 3) signs at **148 bytes = 2.31× ECDSA**, UOV at **96 bytes = 1.5×**. 666 B is the floor among NIST-*finalised* standards only. The error came from treating `quantum_domain_mcp`'s 17-scheme catalogue — which contains none of the nine Round 3 additional-signature candidates — as the whole of NIST's pipeline. §0 is rewritten around a four-way tension (compact / fast / final / EVM-verifiable) rather than a byte count, and now records **HAWK's withdrawal on 2026-07-29**, ten weeks after NIST advanced it to Round 3.
2. **§1(b)** — "`0x0100`/`0x0101` are EIP-8051's `VERIFY_MLDSA`" is **wrong on both halves**. EIP-8051 specifies 0x12/0x13. **`0x0100` is Besu's `P256_VERIFY` (EIP-7951, secp256r1)**, `Address.precompiled(0x0100)`, registered only in `populateForOsaka`. Latent today (Cancun genesis), live misroute on any Osaka upgrade, baked into an `immutable`. New work item.
3. **§1(e) NEW** — the hardcoded ML-DSA-65 signature length **3,309 is not FIPS 204**; the standard is **3,293**, so the skeleton's only input-validation rule rejects conformant signatures. Wrong in four files.
4. **§2** — "pure-Solidity verification is 4.9–8.1M gas, so Falcon wins" is **superseded**. Fireblocks publishes an open-source, formally-verified, ACVP-tested ML-DSA-44 verifier at **1,226,311 gas, measured** (baseline ETHDILITHIUM 8,094,831). **No published pure-EVM figure exists for Falcon at any gas price**, and the only public Solidity Falcon verifier is a PoC needing a 500M-gas block. Falcon wins on size and signing latency and **loses on on-chain verifiability**; the conclusion now depends on whether LXON forks Besu. §2 records that Besu's 134 plugin services cannot register a precompile (verified against the tree) and adds the `TransactionValidatorService` plugin route as a zero-fork alternative.

**One further correction, and it is mine, not v0.2's.** v0.2 labelled FN-DSA-512 "FIPS 206 **draft**" and §7 decision 1 said "it is not final" — both correct. My first pass at this v0.3 rewrite changed those to "FIPS 206 final", which is wrong: NIST CSRC's standardisation page says verbatim *"FALCON was also selected and will be published in FIPS 206 (in development)"* against *"FIPS 203, FIPS 204, and FIPS 205 … were published August 13, 2024"*, the IETF COSE Falcon draft (2026-03-15) expects publication "late 2026 early 2027", and `pqc_algorithm_deep_dive` returns `status: "draft"`. Reverted in §0 with sources. The consequence is not cosmetic: **Falcon is in the same pre-final category as SQIsign, so the four-way tension in §0 has no "final + compact" row at all, and ML-DSA-44 becomes the only scheme holding three of the four properties.** That strengthens §7 decision 1 and weakens §3's pick.

Evidence base for v0.3: files in this repo read today, Besu source read via the GitHub API (redirect-controlled), npm registry, cloned third-party verifiers, NIST/IETF/FIPS primary documents, and `quantum_domain_mcp` + `blockchain_expert` outputs — including four unusable or fabricated tool results, recorded in the companion doc §9. No live-chain state was re-measured: chain 724 was restarted from an empty volume (blocks 1–242,493 gone, so the October 2026 PQC broadcast addresses no longer exist on any live chain) and `rpc.lxon.in` / `explorer.lxon.in/api/eth-rpc` were unreachable.

**Changelog v0.1 → v0.2.** Owner asked for faster operation, smaller signatures and blocks ("like normal crypto"), and a honeypot. Three changes: primary signature scheme moved from SLH-DSA-SHA2-192s to **FN-DSA-512 (Falcon-512)** — 24.4× smaller signatures, 24.4× less calldata gas; because signatures now fit in calldata cheaply, the off-chain-commitment machinery (v0.1 §4 C1) is demoted from *mandatory* to *optional*; and a new §6 integrates the existing `crates/honeypot` deception layer and the `HoneyEncryption` DTE already in `pqc.ts`. A new blocking finding is recorded in §1(d): the PQC dependency is absent from disk, so nothing in the TS PQC surface can run.

---

## 0. The size floor — read this before anything else

> **CORRECTED 2026-11-03, after deep research.** This section originally claimed 666 bytes was the floor for *any* NIST-track PQC scheme and that "like normal crypto" was unreachable. **That was wrong.** The floor in the NIST pipeline is **148 bytes (SQIsign-L1, 2.31× ECDSA)**, and one candidate reaches **96 bytes (UOV, 1.5×)**. 666 bytes is the floor only among NIST-*finalised* standards. The original number came from `quantum_domain_mcp`'s 17-scheme catalogue, which contains none of the nine Round 3 additional-signature candidates — I presented a tool's coverage limit as a property of cryptography. Full evidence, sources and the corrected trade-off: [`pqc-size-and-evm-gas-research.md`](./pqc-size-and-evm-gas-research.md).

**The floor is not a byte count. It is a four-way tension: compact / fast to sign / standardisation-final / verifiable on today's EVM. No scheme satisfies all four.**

| | compact | fast signing | **final** standard | EVM-verifiable today |
|---|---|---|---|---|
| SQIsign-L1 (148 B) | **yes** | no — 7× jitter, 30–220 ms | no — Round 3 | **no impl exists** |
| UOV (96 B) | **yes** | yes | no — Round 3 | no impl; pk is ~67 KB |
| FN-DSA-512 (666 B) | mid | **yes** — sub-ms | **no — FIPS 206 still in development** | **no** — needs a fork |
| ML-DSA-44 (2,420 B) | no | **yes** — fastest verifier | **yes** — FIPS 204 final | **yes — 1,226,311 gas** |
| SLH-DSA-192s (16,224 B) | no | no | **yes** — FIPS 205 final | no published number |

The two rows that matter for LXON point in opposite directions. **ML-DSA is the only scheme with a working pure-EVM verifier (open source, formally verified, KAT-tested, 1.23M gas = 4.09% of a 30M block in compute)** — and it is the scheme the owner ruled out. **Falcon is the only candidate that is both compact and fast to sign** — and it has no viable pure-EVM verifier at any gas price; the only public Solidity implementation is a self-described PoC whose test config raises `blockGasLimit` to 500,000,000 and disables the EIP-170 size limit. Compactness and on-chain verifiability are currently anti-correlated.

**ML-DSA-44 is the only row in that table with three of the four properties.** Every compact option fails on standardisation *and* on EVM verifiability simultaneously. That is the strongest single argument in this design, and it argues against the scheme v0.2 picked.

> **FIPS 206 is not final.** Corrected 2026-11-03 — the earlier version of this document (and the first draft of the research companion) called FN-DSA-512 "FIPS 206 final". It is not. [NIST CSRC's PQC standardisation page](https://csrc.nist.gov/projects/post-quantum-cryptography/post-quantum-cryptography-standardization) says verbatim: *"FIPS 203, FIPS 204, and FIPS 205 … were published August 13, 2024"* and *"FALCON was also selected and will be published in FIPS 206 (in development)"*; the IETF [`draft-ietf-cose-falcon-04`](https://datatracker.ietf.org/doc/html/draft-ietf-cose-falcon-04) (2026-03-15) says "expected to be published in late 2026 early 2027"; the draft was submitted for internal approval 2025-08-28; `pqc_algorithm_deep_dive("FN-DSA-512")` returns `"fips": "FIPS 206 (draft)"`, `"status": "draft"`. All three links were re-verified HTTP 200 on 2026-11-03 (two URLs first written into this note from memory — a wolfSSL page and a `csrc.nist.gov/pubs/fips/206/upd1` page — returned 404 and have been removed). **§7 decision 1 was already correct on this point and §0 was not.** Falcon is a *selected* algorithm awaiting its standard, in the same pre-final category as SQIsign — it is further along, but the gap to FIPS 204/205 is real.

Full size table (all NIST-track schemes, sourced):

| Scheme | sig | ×3 attestors | ×3 calldata gas | vs Falcon | vs ECDSA | Status |
|---|---|---|---|---|---|---|
| UOV (cat 1) | 96 | 288 B | 4,596 | 0.14× | 1.50× | Round 3; pk ~67 KB |
| SQIsign-L1 | 148 | 444 B | 7,083 | 0.22× | 2.31× | Round 3 |
| SQIsign-L3 | 224 | 672 B | 10,722 | 0.34× | 3.50× | Round 3 |
| HAWK-512 | 555 | 1,665 B | 26,562 | 0.83× | 8.67× | **WITHDRAWN 2026-07-29** |
| ECDSA secp256k1 (today's bridge) | 64 | 192 B | 3,063 | 0.10× | 1.00× | baseline |
| **FN-DSA-512 (Falcon)** | **666** | **1,998 B** | **31,875** | **1.0×** | **10.41×** | FIPS 206 **in development** |
| FN-DSA-1024 (Falcon) | 1280 | 3,840 B | 61,260 | 1.92× | 20.00× | FIPS 206 **in development** |
| HAETAE-120 | 1474 | 4,422 B | 70,545 | 2.21× | 23.03× | Round 1 only |
| ML-DSA-44 (FIPS 204, Cat 2) | 2420 | 7,260 B | 115,821 | 3.63× | 37.81× | final |
| ML-DSA-65 (FIPS 204, Cat 3) | **3293** | 9,879 B | 157,602 | 4.94× | 51.45× | final |
| SLH-DSA-SHA2-128s (FIPS 205) | 7856 | 23,568 B | 375,984 | 11.80× | 122.75× | final |
| SLH-DSA-SHA2-192s (FIPS 205) — v0.1 pick | 16224 | 48,672 B | 776,472 | 24.36× | 253.50× | final |

Computed with EIP-2028 pricing at the expected zero-byte rate for high-entropy data (`16·(n − n/256) + 4·(n/256)`, i.e. 1/256 of bytes zero); the all-non-zero worst case is 0.3% higher. Every value in this table was recomputed from that formula, not extrapolated from a neighbouring row.

Two corrections against the earlier version of this table: **ML-DSA-65 is 3,293 bytes, not 3,309** (FIPS 204; the repo hardcodes 3,309 in four files — see §1(e)), and **HAETAE-120 at 1,474 bytes is 2.2× worse than Falcon**, so it is not a compact alternative and did not advance past Round 1.

Falcon-512 ×3 is **1,998 bytes and 0.106% of a 30M-gas block**; SLH-DSA-192s ×3 was 48,672 bytes and 2.59%. The v0.1→v0.2 size win is real and large. But the residual gap to ECDSA is **2.31×, not 10.4×**, if LXON is willing to build on a Round 3 candidate and write its own EVM verifier — and that willingness is an owner decision (§7), not an engineering default.

**HAWK is in this table as a warning, not an option.** On 2026-05-14 it was one of nine candidates advanced to NIST Round 3, with the best compact profile of the lattice entries. On 2026-07-28 Anthropic published an attack that halves its effective keysize, found by an AI model. On 2026-07-29 the team withdrew it. **Ten weeks from "Round 3 candidate" to "insecure, withdrawn."** Any size-driven choice of a non-finalised scheme is a choice that can be invalidated inside a quarter. SQIsign-L1's 148 bytes is a Round 3 candidate; Falcon's 666 bytes is a *selected* algorithm whose standard was submitted for approval in August 2025 but is still not published. **Falcon is further along the same pre-final path, not off it** — and HAWK is what that path can do.

---

## 1. Measured baseline — what exists today

Four findings, each verified by reading or executing repo code today.

**(a) The pure-Solidity verifier unconditionally returns false.**
`contracts/src/satellite/pq/MlDsaVerifierPure.sol:72` is `return false;`. Its header calls it "a *skeleton*", says the real NTT arithmetic is "~2000 lines" to be added "before mainnet", and quotes ~8.1M gas for Dilithium / ~4.9M for the Keccak-based ETHDilithium variant.

**(b) The precompile path cannot exist on this chain — and worse, it points at the wrong precompile.**

*CORRECTED 2026-11-03. This finding originally said `0x0100`/`0x0101` were EIP-8051's addresses. They are not.*

`MlDsaVerifierPrecompile.sol:18-19` sets `PRECOMPILE_MLDSA = address(0x0100)`. **`0x0100` is P256VERIFY (EIP-7951) — a secp256r1 ECDSA verifier — not ML-DSA.** Verified in Besu source:

```java
// datatypes/.../Address.java:91-92
/** Precompile address for P256_VERIFY. */
public static final Address P256_VERIFY = Address.precompiled(0x0100);

// evm/.../precompile/MainnetPrecompiledContracts.java:205-206, inside populateForOsaka(...)
// EIP-7951 - secp256r1 P256VERIFY
registry.put(P256_VERIFY, new P256VerifyPrecompiledContract(gasCalculator));
```

EIP-8051 actually specifies **0x12/0x13** at 4,500 gas; EIP-8355 specifies **0x12 (ML-DSA-44) / 0x13 (65) / 0x14 (87)**; EIP-7885 claims **0x12–0x15** for NTT. Three Draft EIPs collide on the same range, and the repo targets none of them.

Currently latent, because P256_VERIFY is registered **only in `populateForOsaka`** and `lxon-evm-node/besu/testnet/{725,726}/genesis.json` set `cancunTime: 0` with no Prague or Osaka timestamp on `hyperledger/besu:26.10.0`. `0x0100` is empty, the `staticcall` fails, and `MlDsaVerifierFactory.sol:31-37` correctly falls back to the skeleton.

**It goes live on any Osaka upgrade.** The probe is `try pc.verify(...) returns (bool) { precompileExists = true; } catch { precompileExists = false; }` — it treats *any* non-reverting return as proof an ML-DSA precompile exists, and P256VERIFY returns a value on malformed input rather than reverting. `usingPrecompile` and `verifier` are `immutable`, so the misroute is baked in permanently at construction. It fails closed (a P256 verifier returns 0 for an ML-DSA signature), but the observable flag would report "precompile-accelerated ML-DSA active" over a lane that verifies nothing.

Fix: the probe must verify a **known-answer signature and require `true`**, not merely require a non-revert; and the addresses must be re-read from whichever EIP actually ships.

**(c) The test suite only asserts the negative.**
`contracts/test/satellite/MlDsaVerifier.t.sol` has three tests; all assert `assertFalse` or `assertTrue(v != address(0))`. Nothing asserts a valid signature verifies. Its comment defers "real ML-DSA KAT vectors" to a future integration. No NIST known-answer vectors exist anywhere in the repo. For scale, the Fireblocks verifier ships 320 tests including the official NIST ACVP vector sets run on-chain with must-reject cases, the Wycheproof corpus, 62 Z3-proved arithmetic properties (794 claims) pinned to the shipped source, 64 Lean 4 theorems on EVM opcode semantics, and 50 one-at-a-time mutations. See [`pqc-size-and-evm-gas-research.md`](./pqc-size-and-evm-gas-research.md) §3.1.

**(d) NEW in v0.2 — the PQC dependency is absent from disk, so nothing runs.**
`package.json:21` declares `"@noble/post-quantum": "^0.7.1"`. Both `apps/lxon-blockchain/node_modules/@noble/post-quantum` and `sdk/typescript/node_modules/@noble/post-quantum` are **dangling symlinks** into a pnpm store path that does not exist. Control: `@noble/curves` in the same directory resolves correctly, so the store itself is healthy and this is specific to one package. `@noble/post-quantum@0.7.1` exists on npm and is `latest` (verified against the registry), so this is a broken store link, not a bad version — `pnpm install` is the whole fix.

Measured, not inferred:

```
$ node -e "require.resolve('@noble/post-quantum')"
FAILED: MODULE_NOT_FOUND

$ node -e "new (require('./dist/crypto/pqc.js').MLDSA65)().keygen()"
THREW after 1 ms -> ERR_MODULE_NOT_FOUND
  Cannot find package '@noble/post-quantum' imported from
  /Users/adikamble/LXON/LXON/apps/lxon-blockchain/dist/crypto/pqc.js
```

`PQ_STATUS.live` is `false`, which is accurate. Every scheme in `PQ_STATUS.schemes` is marked `implemented` — `mlKem768`, `mlDsa65`, `hybrid`, `honey` — and none of them can execute. `dist/` loads because the import is dynamic (`await import(...)` at `pqc.ts:44,48`), so the failure surfaces at first use rather than at require time.

**Consequence for this design: no scheme choice can be benchmarked on this machine until `pnpm install` restores the package.** §4 is explicit about which speed claims are measured and which are not.

**(e) NEW 2026-11-03 — the hardcoded ML-DSA-65 signature length is not FIPS 204.**
FIPS 204 ML-DSA-65 signatures are **3,293 bytes**. The repo hardcodes **3,309** in four places:

```
IMlDsaVerifier.sol:22          @param signature  ML-DSA-65 signature (3309 bytes, raw)
MlDsaVerifierPure.sol:67       if (signature.length != 3309) return false;
MlDsaVerifierFactory.sol:27    try pc.verify(new bytes(1952), new bytes(1), new bytes(3309))
test/satellite/MlDsaVerifier.t.sol:23   factory.verify(new bytes(1952), new bytes(1), new bytes(3309))
```

A conformant FIPS 204 ML-DSA-65 signature is rejected by the length check at line 67 — the skeleton's only substantive behaviour is wrong on its own chosen parameter set. The public key length (1,952) is correct. The wrong figure is circulating in secondary literature (arXiv 2601.17785 Table I prints 3,309 for ML-DSA-65 and 4,627 for ML-DSA-87 vs FIPS 204's 3,293 and 4,595), so it was most likely copied from a paper. **Every parameter must be sourced from the FIPS document, not from a benchmark table.**

**Net of (a)–(e):** on-chain PQC verification has never returned `true`, the precompile probe is aimed at a secp256r1 verifier, the one input-validation rule in the skeleton rejects conformant signatures, and off-chain PQC signing currently cannot run at all. The 35 `PQC_*_COMPLETE.md` / `*_PRODUCTION_READY_REPORT.md` files at the repo root describe a capability that does not exist in either direction.

**Also broken:** `crates/crypto-pqc` is deleted from the working tree (six files ` D `, all present at HEAD) while seven workspace crates — `l2-sequencer`, `l3-mint`, `p2p`, `privacy`, `space-node`, `space-relay`, `storage` — declare `crypto-pqc = { path = "../crypto-pqc" }`. The Rust workspace cannot build in the main tree. Both worktrees have it intact.

---

## 2. Why ML-DSA is still not the answer (and why "it's old" isn't the reason)

ML-DSA is not old: `pqc_algorithm_deep_dive` returns FIPS 204, MLWE + SIS, NIST level 3, 207 classical / 207 quantum bits, status `final`. Both quantum tools recommend it as the finance default — `cross_domain_synthesis` says "Deploy ML-KEM-768 hybrid TLS + ML-DSA-65 hybrid signatures", and `pqc_migration_planner` Phase 2 says the same.

The reason to move off it is size and EVM cost, which is exactly what the owner asked about:

- ML-DSA-65's signature is **3,293 bytes** (FIPS 204), 4.9× Falcon's, and its public key is 1,952 bytes vs Falcon's 897.
- ML-DSA-44 is smaller (2,420 B, Cat 2, `final`) but still 3.6× Falcon and still ML-DSA.

> **CORRECTED 2026-11-03.** This section originally cited "pure-Solidity verification is 4.9–8.1M gas per the repo's own header" and concluded "Falcon wins on the stated requirement." Both need qualifying, and the research overturned the conclusion's direction.
>
> The 4.9–8.1M figure is the repo header's quote of ZKNox's ETHDILITHIUM, which Fireblocks measured at **8,094,831 gas** and then beat with an open-source ML-DSA-44 verifier at **1,226,311 gas of compute, measured** — 1,286,237 gas or **4.29% of a 30M block** for a full transaction once the key is pre-deployed as a blob contract, plus a one-time ~4.11M-gas code deposit for the 20,545-byte expanded public key. It is unaudited research code, but it is formally verified (Z3 + Lean 4), KAT-tested against NIST ACVP vectors on-chain, and it works on today's EVM with no fork.
>
> **Falcon has no equivalent.** There is no published pure-EVM gas figure for Falcon-512 at any size, the only public Solidity implementation (`lacchain/sol-falcon-verify`) is a self-described PoC that needs `blockGasLimit: 500_000_000` and `allowUnlimitedContractSize: true` to run its own tests, and EIP-7619 states plainly that the Solidity path "does not scale due to the required high amount of gas." Cloudflare's assessment is that FN-DSA "is difficult to implement... in a timing side-channel secure way," which is why they shipped ML-DSA.
>
> So **Falcon wins on signature size and signing latency and loses on on-chain verifiability.** It only wins overall if LXON forks Besu to add a precompile — and that is a permanent maintenance cost and a chain-split risk, not a code change. See §5 and the research doc §6. Besu exposes 134 plugin service interfaces and **none of them can register a precompile** (verified against the `besu-eth/besu` tree: 8,893 paths, 47 precompile `.java` files, 0 under any plugin path), so route A means patching `MainnetPrecompiledContractRegistries` and shipping a custom image to every node.
>
> A cheaper route exists and is not yet in this design: Besu's `TransactionValidatorService` / `PluginTransactionSelector` **are** plugin-facing. A plugin can enforce "no transaction enters a block without a valid PQC attestation" at zero fork cost. It cannot let a *contract* verify a PQC signature, so it does not serve the bridge's on-chain quorum check — but it is the only PQC enforcement LXON can ship without forking. Added to §7 as a decision.

The honest statement of the trade-off is in §0: compact / fast / final / EVM-verifiable, pick at most two. §5 does not soften that.

---

## 3. Scheme selection (v0.2)

### Primary signature: FN-DSA-512 (Falcon-512)

`pqc_algorithm_deep_dive("FN-DSA-512")` → FIPS 206 (draft), NTRU lattice, NIST level 1, pk 897 / sk 1281 / sig 666, 143 classical and 143 quantum bits. `quantum_verifier(pqc-conformance)` on those three sizes → **CONFORMANT**, all PASS.

Four reasons it is the right pick for this requirement:

1. **Smallest signature of any NIST-track scheme** — 666 B, 24.4× smaller than the v0.1 pick, 5× smaller than ML-DSA-65.
2. **Fastest sign and verify** of the candidates. Directional evidence only, see §4.
3. **Already implemented in this repo.** `src/crypto/quantum-resistant.ts:69-71` loads `@noble/post-quantum/falcon.js`; `HashSignatureScheme.falcon512()` at :110-112; `QuantumResistantManager` lists `'falcon-512'` in its supported schemes at :258 and dispatches keygen/sign at :267-288. Choosing Falcon means wiring up code that exists, not writing a new adapter. This is the single largest schedule advantage and it directly serves "faster working".
4. **Small enough that signatures can go on-chain directly.** 3 × 666 B = 1,998 B ≈ 31,968 gas. That is ordinary calldata. It removes the need for v0.1's commitment-and-fraud-proof machinery as a *requirement*.

Two source bugs to fix while in there, both found by reading the file:
- `quantum-resistant.ts:110` documents "654-byte signature" while :140-142 says "666 is the maximum encoded size". The MCP agrees with 666. Reconcile to 666.
- The adapter class is named `HashSignatureScheme` (:98) but serves Falcon, which is an NTRU *lattice* scheme, not hash-based. Rename to something scheme-neutral (`CompactSignatureScheme`) — the current name will mislead the next reader into assuming a hash-based security argument.

### Confidentiality: ML-KEM-768 ⊕ HQC-192 (unchanged from v0.1)

ML-KEM-768 — FIPS 203, `final`, Cat 3, 207 bits, pk 1184 / ct 1088 / ss 32. HQC-192 — NIST IR 8545, code-based, **selected Mar 2025**, Cat 3, pk 4522 / ct 8978 / ss 64. Two unrelated hard problems, so a single-family break does not collapse confidentiality. Combined secret = `KDF(ss_mlkem || ss_hqc)` under distinct domain-separation tags.

Unchanged because the driver is unchanged and it is not a size or speed question: `pqc_migration_planner(dataShelfLifeYears=20, migrationYears=2)` → Mosca `x + y = 22 > z = 8`, **EXPOSED — harvest-now-decrypt-later applies**, margin **−14 years**, dataTypeRisk HIGH. `quantum_threat_timeline` puts CRQC at 1-in-4 by 2030 and 1-in-2 by 2035 (GRI 7th ed., March 2026), with Google warning in March 2026 of arrival by 2029. Chain data is public and permanent, so the harvest has already happened. KEM ciphertexts are ephemeral and never touch calldata, so their size is irrelevant to the block-size requirement.

HQC caveat: `pqc_sidechannel_report(scheme=HQC)` reports ciphertext-independent single-trace passive SCA (ePrint 2025/1897) and fixed-weight vector sampling leakage. Used here on the encapsulation leg only, where decapsulation runs on a server rather than embedded hardware.

### Rejected

- **SLH-DSA-SHA2-192s** — the v0.1 pick. Cryptographically the most conservative option (hash-based, `final`, Cat 3, 48-byte public key) but 16,224-byte signatures are precisely what the owner ruled out. Retain as a *deliberate escalation* if Falcon's draft status becomes a problem or a lattice attack lands; the registry in §5 C3 is what makes that switch cheap.
- **ML-DSA-44 / ML-DSA-65** — see §2.
- **MAYO** — `pqc_algorithm_deep_dive("MAYO-2")` returned `Unknown: MAYO-2` with the 17-entry list of what is standardised. `PQ_STATUS.schemes.mayo` already records the honest reason: "`crates/mayo-binding` declares `pq-mayo = { workspace = true }` but root `Cargo.toml` has no such workspace dependency, and the crate carries zero `#[wasm_bindgen]` attributes — so the shipped `sdk/wasm` blob exports no MAYO functions at all."
- **Classic McEliece** — not standardised, multi-megabyte keys.
- **XMSS** — superseded by FIPS 205 and stateful, which is the wrong property for satellite firmware.

---

## 4. Speed — what is measured and what is not

**Nothing about speed was measured on this machine.** §1(d) is the reason: `@noble/post-quantum` is absent, so no scheme can be executed to time it. Any timing figure I put in this document would be invented, so there are none.

What is evidenced:

- `pqc_algorithm_deep_dive` encodes the trade-off directionally in its own data. `SLH-DSA-SHA2-128s` carries `tradeoff: "small sig, slow sign"`; `SLH-DSA-SHA2-128f` carries `tradeoff: "fast sign, large sig"`. **FN-DSA-512 carries no trade-off warning at all**, which in this dataset means neither axis is penalised.
- The structural reason is sound and independent of the tool: SLH-DSA verification walks a Merkle tree of `h = 66` levels with `k = 33` WOTS+ chains per level, i.e. tens of thousands of hash invocations, whereas Falcon verification is a single lattice operation over a 512-degree NTRU ring. The ordering — Falcon substantially faster than SLH-DSA on both sign and verify — is not in doubt. The *magnitudes* are.

**Action item, Phase 0:** after `pnpm install`, run a benchmark over `['falcon-512', 'slh-dsa-128f', 'ml-dsa-65', 'hybrid-secp256k1-ml-dsa-65']` — all four already exist in `QuantumResistantManager.supportedSchemes` (`quantum-resistant.ts:258`) — recording keygen/sign/verify milliseconds and exact encoded byte lengths, and commit the result. That converts this section from directional evidence into measurement, and it is roughly an hour of work.

One cost that *is* computed rather than estimated: the on-chain calldata figures in §0, which are exact arithmetic from the tool's byte sizes.

---

## 5. Architecture

### C1. Signatures on-chain directly; commitment layer now OPTIONAL

This is the substantive change from v0.1. At 1,998 bytes per three-attestor bundle, PQC signatures fit in ordinary claim calldata. v0.1 required an off-chain bundle plus a 32-byte `keccak256` commitment plus a fraud-proof window, because 48,672 bytes did not fit comfortably. That requirement is lifted.

Recommendation: put the Falcon signatures in the claim calldata, and keep the commitment path available as an optimisation for high-throughput lanes rather than as the core design. Simpler is better, and the simpler design is now affordable.

What does **not** change: verification is still not performed as pure Solidity. A 666-byte signature does not make Falcon verification cheap in the EVM — it makes transmitting it cheap. Falcon verify in Solidity requires fixed-point FFT arithmetic over the NTRU ring; treat that as unavailable until C2 exists.

### C2. Besu precompile `VERIFY_FALCON` at `0x0100`

LXON owns its chain, so a precompile is a genesis/protocol change under its own control — unlike EIP-8051, which will never arrive on a Cancun QBFT network. This is the verification path, for both routine claims and disputes.

Carry over the v0.1 rule that matters: **the fallback must be removal, not a silent fail-closed skeleton.** A verifier that always returns `false` is indistinguishable from a broken one, and it is precisely what produced §1(a)–(c). If the precompile is absent, the registry entry must read `enabled = false` and callers must receive an explicit `SchemeUnavailable` revert — never a `false`.

### C3. Crypto-agility registry

`PqcAlgorithmRegistry`: `schemeId → { fips, family, pkLen, sigLen, nistLevel, status, enabled, minVersion, isCanary }`.

This is more load-bearing in v0.2 than in v0.1, because the primary scheme is now a **draft** standard. When FIPS 206 finalises — or if Falcon is weakened, or the 16 KB signature cost of SLH-DSA becomes acceptable — rotation must be a governance action on a registry row, not a redeployment of every consumer. Nothing in the repo does this today; `MlDsaVerifierFactory` selects one verifier at construction and stores it `immutable`.

`isCanary` is new in v0.2 and exists for §6.

Implements Phase 1 of `pqc_migration_planner` ("Build crypto-agility") as a concrete artefact.

### C4. Hybrid combiner — AND semantics, with a downgrade guard

Both halves must verify. Never `EITHER`: `EITHER` means an attacker who breaks one half wins.

Validated with the tools for the revised pairing rather than carried over from v0.1:

- `quantum_verifier(verificationType=hybrid-scheme, algorithm="FN-DSA-512 + ECDSA-secp256k1", combinationRule=AND, hasDomainSeparation=true, keysIndependentlyGenerated=true, hasDowngradeGuard=true)` → **PASS**, `issues: []`.
- `quantum_tester(mode=hybrid-truth-table, combinationRule=AND)` → four rows, `vulnerabilities: []`: `both valid` accepted; `classical-only` rejected; `PQC-only` rejected; `neither` rejected. Note this test is scheme-agnostic — it enumerates the combination rule, so the same result applied to v0.1's pairing.

The three properties the PASS depends on must be real in code:

- **Domain separation** — distinct tags per `(scheme, chainId, purpose)`. `pqc.ts:17` and `quantum-resistant.ts:49` both use `DOMAIN = 'lxon/v2/pqc-sign'`; the comment says it is shared "so hybrid and single-scheme sigs are not interchangeable". Bump to `lxon/v3/` and extend per purpose.
- **Independent key generation** — the ECDSA and Falcon keys come from separate derivations, not one seed split two ways.
- **Downgrade guard** — monotonic `minSchemeVersion`, enforced on-chain, so that once raised, classical-only or weaker attestations are rejected. The planner's Phase 4 ("`minSchemeVersion` rejects classical-only") and a control LXON has previously been missing.

One Falcon-specific correctness requirement that does not apply to the other schemes: **signatures are variable-length.** `quantum-resistant.ts:140-142` notes "Falcon's are variable, so 666 is the maximum encoded size, not [a fixed length]". The registry's `sigLen` must therefore be a *maximum* with a canonical encoding rule, and the verifier must reject non-canonical encodings — otherwise the same signature admits multiple byte representations, which is a malleability hole that breaks any `claimId` or commitment derived from signature bytes.

### C5. KAT-gated CI

FIPS 206 known-answer vectors as a hard build gate, plus at least one test asserting a **valid** signature returns **true**. Cheapest item in the design, and the specific control whose absence produced §1(c). It also converts "we implement Falcon" from an assertion into a measurement — which the repo has never done for any PQC scheme, and which §4 shows is still outstanding for speed.

---

## 6. Honeypot integration (new in v0.2)

LXON already has both halves of this; the work is connecting them to PQC rather than building a deception layer from scratch.

**What exists.** `crates/honeypot` — 267 lines across `lib.rs` (9), `alert.rs` (33), `evidence.rs` (132), `fake_admin.rs` (52), `fake_rpc.rs` (20), `fake_treasury.rs` (21), plus `bin/lxon-honeypot.rs` and a Dockerfile. It exposes `Alert`, `AlertSink`, `MultiSink`, `TracingAlert`, `WebhookAlert`, `Evidence`, `EvidenceKind`, `EvidenceStore`, and `CANARY = "lxon-canary-7f3a9b2c-do-not-use-real-key"`. Separately, `pqc.ts:262-330` implements `HoneyEncryption` — Juels & Ristenpart 2014 DTE, uniform message distribution, scrypt KDF — whose `decrypt()` returns a `plausible` flag for decoy detection, and whose doc comment states "Wrong passwords yield a plausible-looking decoy of identical shape."

### H1. PQC-signed evidence — highest value, smallest change

`fake_treasury.rs:20` constructs `Evidence::new(..., s.store.signing_key())` — the evidence store already signs each record. Upgrade that signature to FN-DSA-512.

This is the strongest use of PQC in the entire honeypot, and the reasoning is specific: evidence is the one artefact in the system with a genuinely long shelf life. It must remain verifiable years later, potentially in a dispute or prosecution, which is exactly the data class the migration planner flags as HIGH risk. A classical signature over evidence is forgeable by anyone who later obtains CRQC; a Falcon signature is not. One file changes.

### H2. Canary public keys in the attestor registry

Register decoy FN-DSA-512 public keys with `isCanary = true` (the C3 field). They are **structurally excluded from the quorum threshold** — not by a mutable flag an attacker or a compromised admin could flip, but by the threshold computation itself counting only non-canary entries.

Any signature that verifies under a canary key is therefore proof of compromise and can never be a legitimate attestation. Fire an alert through the existing `MultiSink` and record via `EvidenceStore`. Extends the existing `CANARY` constant pattern from a string marker into a cryptographic tripwire.

### H3. Honey-encrypted key material with *structurally valid* decoys

`HoneyEncryption` already produces a decoy "of identical shape". For PQC that bar is higher than for a symmetric secret: a decoy that is merely 897 and 1,281 bytes long is distinguishable in one keygen check, because a real Falcon public key has internal algebraic structure.

Enhancement: derive a **genuine** FN-DSA-512 keypair deterministically from the decoy plaintext, so the decoy validates as a well-formed Falcon key and only fails when actually used against the real registry. The `plausible` flag from `decrypt()` becomes the tripwire — a decryption that yields a plausible-but-decoy key is an attacked keysto, and should alert.

### H4. PQC-authenticated decoy services

`fake_treasury.rs` responds with `<h1>LXON Treasury</h1>` and `{"status":"pending_multisig"}`; `fake_rpc` and `fake_admin` are similarly thin. All three speak classical auth only. An attacker specifically hunting for PQC material would spot the inconsistency immediately, and a decoy that is detectable as a decoy has negative value — it teaches the attacker what the real thing looks like.

Add FN-DSA-512 signatures over decoy responses, under canary keys from H2. The decoys then present exactly the surface a quantum-motivated attacker is scanning for, and touching one is self-reporting.

### H5. Decoy-use detection loop

Two triggers, both feeding the existing `AlertSink` / `EvidenceStore`:
- `HoneyEncryption.decrypt()` returning `plausible = true` (a wrong password was used against real key material).
- Any signature verifying under a canary public key (H2).

Record only, and alert. **Never auto-retaliate and never auto-revoke** — an automated response to a decoy touch is itself an oracle an attacker can probe.

### Hard rules

1. **The honeypot must never hold or touch real signer key material.** Falcon signing is side-channel sensitive (§5, C4 caveat below), and a service whose job is to be attacked is the wrong host for a live signing key. The real signer stays isolated; the honeypot gets canary keys only.
2. **Canary keys must be unable to reach quorum by construction**, per H2.
3. **Decoys must not be able to sign real chain state transitions** — enforced by the same structural exclusion, not by convention.

### Caveat the tooling cannot cover

`pqc_sidechannel_report` accepts only `ML-KEM (Kyber)`, `ML-DSA (Dilithium)`, `HQC`, `SLH-DSA (SPHINCS+)`. **Falcon is not in the enum**, so this toolchain cannot audit the primary scheme's side-channel exposure. That is a real gap, and it is worse in v0.2 than in v0.1 because v0.1's SLH-DSA pick *was* covered. It is also the sharpest form of the trade being made: the owner is buying 24.4× smaller signatures and faster operation with a draft standard whose side-channel profile the available tooling cannot assess.

The known exposure is in the trapdoor sampler — Falcon's Gaussian sampling historically used floating point, which leaked. Mitigation is non-negotiable if Falcon is chosen: **fixed-point sampler only, never floating point**, an independently audited implementation, and signing confined to a host with no untrusted co-tenants. `@noble/post-quantum` is pure TypeScript with no native or WASM binary (per `quantum-resistant.ts`'s header), which avoids C-level leaks but does not by itself make the sampler constant-time — that must be confirmed against the library, not assumed.

---

## 7. Owner decisions required

1. **Accept FIPS 206 draft status?** Falcon is the only scheme that meets the size and speed requirement, and it is not final. `pqc_security_analysis("FN-DSA-512")` returns NIST level 1, target 143 bits, claimed 143 bits, **`marginBits: 0`**, `marginStatus: "ABOVE requirement"`, `cryptanalysisNotes: []`. Read that honestly: it meets the Cat 1 target exactly, with **zero headroom**, and it is Cat 1 where ML-DSA-65 gave Cat 3. The size win is partly paid for in security category, and no tool output changes that arithmetic.
2. **Accept the side-channel audit gap?** §6's caveat. If the answer is no, the honest alternatives are SLH-DSA-SHA2-192s at 24.4× the signature size, or waiting for FIPS 206 to finalise.
3. **Where does the Falcon signing key live?** Fixed-point sampler, isolated host, no untrusted co-tenants. Not on the laptop that already holds all three quorum keys (`lxon-evm-node/besu/validators/validator-{1,2,3}.hex`).
4. **The Besu precompile is a protocol change** needing a fork coordinate and every validator upgraded in lockstep. Only the owner can schedule it, and on a chain whose validator set is three plaintext keys on one machine, the upgrade path is also the key-distribution path.
5. **C1 simplification** — confirm that putting Falcon signatures directly in claim calldata is preferred over retaining v0.1's commitment-and-fraud-proof design. I recommend the simpler path now that it is affordable.

---

## 8. Build order

| Phase | Work | Chain changes | Estimate |
|---|---|---|---|
| **0** | `pnpm install` to restore `@noble/post-quantum` (§1(d)); `git checkout -- crates/crypto-pqc`; benchmark the four schemes in `QuantumResistantManager.supportedSchemes` and commit the numbers (§4); add FIPS 206 KAT vectors + a CI gate + one test asserting a valid signature returns `true`; fix the 654/666 doc bug and rename `HashSignatureScheme`; pin the four floating pragmas | none | 1–2 days |
| 1 | `PqcAlgorithmRegistry` incl. `isCanary` and max-length `sigLen` with a canonical-encoding rule; Falcon-512 wired into `apps/attestor`; hybrid AND combiner with domain separation and independent keygen | none | ~1 week |
| 2 | H1 (PQC-signed evidence) and H2 (canary keys) — both small and independent of the chain work | none | ~2 days |
| 3 | On-chain Falcon signatures in claim calldata (C1); remove the fail-closed Pure skeleton, replace with explicit `SchemeUnavailable` | contract deploy | ~1 week |
| 4 | H3, H4, H5 — structurally valid decoys, PQC-authenticated decoy services, detection loop | none | ~1 week |
| 5 | Besu `VERIFY_FALCON` precompile at `0x0100`, repoint the verifier contract | **protocol fork** | needs owner scheduling |
| 6 | Enforce hybrid, raise `minSchemeVersion`, sunset classical-only, keep read-only ML-DSA/ECDSA verifiers | governance action | per planner Phase 4 |

Phase 0 is worth doing regardless of every decision in §7, and it is now strictly more urgent than in v0.1: §1(d) means the PQC surface is not merely unverified but non-executable. Until `pnpm install` runs, there is no Falcon, no SLH-DSA, no ML-DSA and no ML-KEM in this repo — only code that describes them.

---

## 9. Honest limits of this validation

- `quantum_verifier(hybrid-scheme)` validates the **combination rules**, not the scheme choice. It does not parse the `algorithm` string — it returned PASS for `"SLH-DSA-SHA2-192s + ECDSA-secp256k1"` in v0.1 and for `"FN-DSA-512 + ECDSA-secp256k1"` here. PASS means "AND + domain separation + independent keys + downgrade guard is a sound construction", nothing more.
- `quantum_verifier(pqc-conformance)` and `quantum_tester(pqc-structural)` returned CONFORMANT for Falcon's 897/1281/666 — but those are the numbers `pqc_algorithm_deep_dive` supplied, so this is self-consistency within one server, not independent confirmation.
- `quantum_tester(hybrid-truth-table)` is scheme-agnostic; it enumerates the AND rule, not any signature scheme.
- **No speed claim in this document is measured.** §4 states exactly what evidence exists and what is missing, and why.
- `audit_readiness` on `contracts/src/satellite/pq` returned **35/100, NOT READY**, but scored that directory in isolation: it reported "No test files found" while `contracts/test/satellite/MlDsaVerifier.t.sol` exists one level up, and README / LICENSE / CI live at the repo root. **Discount the number.** The gaps that are real and independently confirmed are the missing KAT vectors and the missing CI gate.
- `scan_contract_security` on the same directory returned 0 CRITICAL / 0 HIGH / 1 MEDIUM / 4 LOW. The MEDIUM (`timestamp-dependence`, `MlDsaVerifierFactory.sol:42`) is a **false positive** — line 42 is the doc comment "Convenience: verify without the caller needing to know the impl." and the file contains no `block.timestamp`. The 4 LOWs are genuine floating pragmas (`^0.8.24` where `foundry.toml` pins `solc_version = "0.8.26"`).
- `predictive_coder(gas-projection)` returned 9,180 gas projected deployment — a generic estimate for four small contracts that models neither calldata nor verification cost. Not used for any conclusion.
- Calldata and byte-size figures are exact arithmetic from the tool's sizes under a stated worst case. Verification gas is **not** estimated anywhere in v0.2, because with Falcon there is no honest basis for one without a precompile to measure against.
- No live-chain state was re-measured. The three addresses in the `DeployPQCContracts.s.sol/724` and `DeployMLDSAKeyStorage.s.sol/724` broadcasts (`0xdf740bee…`, `0x9744b2cb…`, `0x83e44331…`) remain **unverified** — `eth_getCode` could not be run and there is no control read. Separately, the `MLDSAVerifier.sol` / `HybridSignatureVerifier.sol` / `MLDSAKeyStorage.sol` sources those broadcasts reference appear nowhere in `git rev-list --all --objects`, so the scripts cannot compile as the tree stands.

---

## Appendix — tool calls reproduced

`quantum_domain_mcp`: `pqc_algorithm_deep_dive` × 10 (ML-DSA-44, ML-DSA-65, SLH-DSA-SHA2-128s/128f/192s/256s, FN-DSA-512/1024, ML-KEM-768, HQC-192; MAYO-2 rejected as `Unknown`), `pqc_security_analysis(FN-DSA-512)`, `pqc_migration_planner`, `quantum_threat_timeline`, `cross_domain_synthesis(finance)`, `pqc_sidechannel_report` × 2 (SLH-DSA, HQC; **Falcon unavailable in enum**), `quantum_verifier` × 4, `quantum_tester` × 2.

`blockchain_expert`: `scan_contract_security`, `audit_readiness`, `predictive_coder(gas-projection)`.

Files read: `contracts/src/satellite/pq/{MlDsaVerifierPure,MlDsaVerifierPrecompile,MlDsaVerifierFactory}.sol`, `contracts/test/satellite/MlDsaVerifier.t.sol`, `apps/lxon-blockchain/src/crypto/{pqc,quantum-resistant}.ts`, `apps/lxon-blockchain/package.json`, `crates/honeypot/src/{lib,fake_treasury}.rs`, `crates/honeypot/src/*.rs` (line counts), `lxon-evm-node/besu/testnet/{725,726}/genesis.json`, `apps/contracts/foundry.toml`, `apps/contracts/broadcast/{DeployPQCContracts,DeployMLDSAKeyStorage,ConfigureHybridMode}.s.sol/724/run-latest.json`.

Executed: `node -e require.resolve('@noble/post-quantum')`, the `dist/crypto/pqc.js` keygen probe, and the symlink/control checks in §1(d).
