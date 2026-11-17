# LXON PQC Program Specification

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-05 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x9b15fee95995a15da2d64d8e2958f9792d5d6a25` - v4.1 attested bridge on 724
>
> The control that makes those empty reads evidence, measured by the same script on the same day: the v4.1 bridge on Polygon 137 reads 19105 bytes and wLXON reads 2106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
Version: 0.1 — program specification
Date: 2026-11-03
Status: DRAFT, awaiting owner review. Contains one open decision (D1) that blocks Phase 2 and beyond.
Author: Qoder (side-chat session, main session `a860f692`)

Self-review performed 2026-11-03 after the first write: all 30 calldata figures (22 in §2.1, 8 in §2.3), the 10 non-baseline signature ratios, and every gas total and byte delta recomputed from the underlying byte counts; all 12 internal `§` references checked against real headings (one pointed at §9 instead of §10.1, two cited line numbers as if they were section numbers — all three fixed); the `[M]` repository counts re-run (4 tracked `satellite/pq` files, `contracts/` untracked, 14 files hardcoding `3309`, 3 tests in `MlDsaVerifier.t.sol` all asserting the negative) and the `[M]` chain reads re-run against both chains. The 137 reads reproduced exactly. The 724 block number had moved from 1,971 to 2,367 and is now marked perishable in §4.2, with the assertion moved onto the property that does not move.

Related documents, none of which this replaces:

| Document | Role |
|---|---|
| [`pqc-v2-helios-q.md`](./pqc-v2-helios-q.md) v0.3 | The scheme design. Its §3 picks FN-DSA-512, which survives below **only** as option B, at the cost of a permanent Besu fork. Its §5 C1 assumes signatures go in claim calldata; §3 A below reverses that. |
| [`pqc-size-and-evm-gas-research.md`](./pqc-size-and-evm-gas-research.md) | The deep-research evidence base: size tables, EVM gas, Besu extensibility, HAWK. |
| **this file** | The program spec: what gets built, in what order, against which constraints, and what is still undecided. |

Every number below is tagged `[M]` measured by a command in this session, `[S]` taken from a cited primary source, or `[I]` inferred/arithmetic. Nothing is labelled `[M]` unless a command produced it here.

---

## 0. Summary

LXON has a PQC layer that has never worked. On-chain, `MlDsaVerifierPure.sol:72` returns `false` unconditionally and has done so since 13 September. Off-chain, `@noble/post-quantum` is absent from every package that declares it, so all four schemes `PQ_STATUS` reports as `implemented` throw on first use. Six deploy scripts import three contracts that do not exist on disk.

The owner's requirement is a **compact, non-ML-DSA signature that behaves "like normal crypto"**. This spec corrects a claim made earlier in the same investigation — that the requirement is unsatisfiable. **It is satisfiable on size.** It is not satisfiable on size *and* on-chain verifiability *and* final standardisation simultaneously. §2 shows the arithmetic; §3 shows the three architectures that resolve the tension differently.

The single most consequential new finding: **MAYO is the only compact non-ML-DSA scheme for which an EVM verifier has ever been written**, and that implementation is declared `UNLICENSED` and suppresses EIP-170. It is proof that the thing is possible and it cannot be used.

---

## 1. Requirements

Owner requirements, in their own words, with what each one constrains:

1. **"don't use old type of ML-DSA"** — excludes ML-DSA-44/65/87. Note this instruction was provisionally reversed in the main session on 2026-11-03 when ML-DSA-44 was selected; §7 D1 reopens it, because the reversal was made on the stated premise that no compact non-ML-DSA option exists, and that premise is wrong.
2. **"i want a faster working"** — signing latency on the block-production critical path, and verification latency for attestors.
3. **"signature and block size i want lower like normal crypto"** — signature and block growth comparable to secp256k1's 64-byte signature.
4. **"also add honeypot in that"** — the deception layer in `pqc-v2-helios-q.md` §6. Unaffected by any choice in this spec; it is orthogonal and carries into every option.

Derived requirement from the design doc, not the owner: on-chain verification exists to serve **the bridge's three-attestor quorum check**. `pqc-v2-helios-q.md` §5 C1 sizes the bundle at "1,998 bytes per three-attestor bundle", and its §2 states the plugin route "cannot let a *contract* verify a PQC signature, so it does not serve the bridge's on-chain quorum check". Everything in §2.3 is costed against that use.

---

## 2. The scheme landscape

### 2.1 Sizes

`sig ×` is the ratio to a 64-byte ECDSA (secp256k1 `r‖s`) signature. `cd(n)` is EIP-2028 calldata gas at the expected zero-byte rate for high-entropy data: `cd(n) = round((n − n/256)·16 + (n/256)·4)`. The all-non-zero worst case is 0.3% higher. All `cd` values are `[I]` — computed from `[S]` byte counts by the formula above.

| Scheme | Family | Status | pk (B) | sig (B) | sig × | cd(pk) | cd(sig) |
|---|---|---|---:|---:|---:|---:|---:|
| ECDSA secp256k1 | ECDLP | baseline | 33 | 64 | 1.00× | 526 | 1,021 |
| UOV (cat 1) | multivariate | R3 candidate | ~67,000 | **96** | **1.50×** | 1,068,859 | 1,532 |
| SQIsign-L1 | isogeny/quaternion | R3 candidate | **65** | **148** | **2.31×** | 1,037 | 2,361 |
| MAYO_2 | multivariate | R3 candidate | 2,928 | **239** | 3.73× | 46,711 | 3,813 |
| MAYO_1 | multivariate | R3 candidate | 1,456 | 464 | 7.25× | 23,228 | 7,402 |
| FN-DSA-512 (Falcon) | NTRU lattice | selected; FIPS 206 **in development** | 897 | 666 | 10.41× | 14,310 | 10,625 |
| MAYO_3 | multivariate | R3 candidate | 2,986 | 681 | 10.64× | 47,636 | 10,864 |
| MAYO_5 | multivariate | R3 candidate | 5,554 | 964 | 15.06× | 88,604 | 15,379 |
| ML-DSA-44 | MLWE + SIS | **FIPS 204 FINAL** | 1,312 | 2,420 | 37.81× | 20,930 | 38,607 |
| ML-DSA-65 | MLWE + SIS | FIPS 204 FINAL | 1,952 | 3,293 | 51.45× | 31,140 | 52,534 |
| SLH-DSA-SHA2-128s | hash-based | FIPS 205 FINAL | 32 | 7,856 | 122.75× | 510 | 125,328 |

Sources: MAYO from [pqmayo.org/params-times](https://pqmayo.org/params-times/) `[S]` — MAYO_one L1 pk 1,456 / sk 24 / sig 464; MAYO_two L1 pk 2,928 / sk 24 / sig 239; MAYO_three L3 pk 2,986 / sig 681; MAYO_five L5 pk 5,554 / sig 964. SQIsign-L1 from the [NIST Round 2 spec](https://csrc.nist.gov/csrc/media/Projects/pqc-dig-sig/documents/round-2/spec-files/sqisign-spec-round2-web.pdf) Table 1 `[S]`. UOV from [Cloudflare](https://blog.cloudflare.com/another-look-at-pq-signatures/) `[S]`. ML-DSA / SLH-DSA from FIPS 204 / 205 `[S]`.

**Recorded discrepancy.** [arXiv 2609.24689](https://arxiv.org/html/2609.24689v1) Table 4 gives MAYO-1 as pk 1,420 B / sig 454 B, against pqmayo.org's 1,456 / 464. This is a Round-2-versus-Round-3 parameter difference. This spec uses pqmayo.org, which states its figures are the Round-3 submission. Anyone re-deriving these numbers must say which round they used.

**UOV's public key is unsettled.** Cloudflare says ~67 kB; ScienceDirect and arXiv 2609.24689 say ~272,000 B. Both are cited in the research doc. Either figure makes UOV's key unusable for a registry that stores three of them on-chain, which is why UOV is not carried forward despite having the smallest signature in existence.

**Every finalised NIST PQC signature standard is ≥ 2,420 bytes.** NIST CSRC states verbatim: *"FIPS 203, FIPS 204, and FIPS 205 … were published August 13, 2024"* and *"FALCON was also selected and will be published in FIPS 206 (in development)"* `[S]`. There is no "final and compact" row in the table above, and there will not be one until FIPS 206 publishes.

### 2.2 What is achievable

The owner's size requirement **is** met by three non-ML-DSA schemes: UOV at 1.50×, SQIsign-L1 at 2.31×, MAYO_2 at 3.73×. At 2,361 calldata gas, a SQIsign-L1 signature costs 2.3× an ECDSA signature to post — the same order of magnitude, not a different one.

The earlier claim that "no scheme in existence satisfies both" conflated three separate properties. The correct statement:

> Compact and non-ML-DSA is achievable. Compact, non-ML-DSA, **and verifiable inside LXON's current EVM** is not achievable with anything that exists. Compact, non-ML-DSA, and **finalised** is not achievable either — nothing compact is finalised.

### 2.3 Cost of a three-attestor bridge claim

This is the number that decides the architecture. Calldata is `[I]` from the formula; compute is `[S]` where a measurement exists and **absent** where none does.

| Scheme | 3 sigs (B) | cd(3 sigs) | 3 pks (B) | cd(3 pks) | verify compute | full claim |
|---|---:|---:|---:|---:|---|---|
| SQIsign-L1 | 444 | 7,083 | 195 | 3,111 | **no figure exists** | unknown |
| MAYO_2 | 717 | 11,438 | 8,784 | 140,132 | **no figure exists** | unknown |
| FN-DSA-512 | 1,998 | 31,874 | 2,691 | 42,930 | **no figure exists** | unknown |
| ML-DSA-44 | 7,260 | 115,820 | 3,936 | 62,792 | 3 × 1,226,311 = 3,678,933 `[S]` | **3,815,753** `[I]` |

ML-DSA-44 full claim = `21,000` base + `115,820` calldata + `3,678,933` compute = **3,815,753 gas**, assuming public keys are pre-registered and not resent per claim. Against chain 724's measured `gasLimit` of `0x1c9c380` = **30,000,000** `[M]`, that is **12.72% of a block, ceiling 7 claims per block**.

The 1,226,311 figure is Fireblocks' published measurement for ML-DSA-44 `[S]`, valid **only** at their build settings — see §6.3. At LXON's settings it will differ, in an unmeasured direction.

Note the inversion in the calldata column: SQIsign-L1's whole three-attestor bundle costs **10,194 gas of calldata** against ML-DSA-44's **178,612**. On calldata alone the compact schemes are 17.5× cheaper. What kills them is that nobody has published a compute figure, because nobody has a working verifier.

### 2.4 On-chain verifiers: what actually exists

Established by GitHub API repository search `[M]`:

| Query | total_count |
|---|---:|
| `MAYO solidity verifier` | **1** |
| `UOV solidity signature` | **0** |
| `multivariate signature solidity evm` | **0** |
| `SQIsign solidity` | **0** |

The single hit is [`ruslan-ilesik/poqeth`](https://github.com/ruslan-ilesik/poqeth) (36 stars, last pushed 2025-08-18, 109,727 KB), accompanying [ePrint 2025/091](https://eprint.iacr.org/2025/091) and ACM DOI 10.1145/3708821.3736193. It implements W-OTS+, XMSS, SPHINCS+ and **MAYO** verification in the EVM, plus "naysayer" optimistic variants of each.

Three facts about it, each verified with a control `[M]`:

1. **It cannot be used.** The GitHub API reports `license: None`. The repository root contains no `LICENSE` file — the same query against `fireblocks-labs/evm-ml-dsa-verifier` returns `LICENSE` at 2,888 bytes, which is the control proving the query works. And `src/mayo/Mayo.sol:1` carries `// SPDX-License-Identifier: UNLICENSED`, an explicit declaration by the authors. All rights reserved: no right to copy, modify, or distribute.
2. **It does not fit a normal chain.** Its `foundry.toml` sets `gas_limit = "18446744073709551615"` (u64 max), `memory_limit = 99999999999`, and `ignored_error_codes = [..., "code-size", ...]`. Suppressing `code-size` means the compiled verifier exceeds EIP-170's 24,576-byte deployment cap. `[M]` from the config; the inference that this is *why* it is suppressed is `[I]`.
3. **Its authors say full on-chain verification is the wrong mode.** README, verbatim: *"Our practical performance evaluation shows that full on-chain verification is often prohibitively costly. Naysayer proofs (FC'24) allow a novel optimistic verification mode. We observe that the Naysayer verification mode is generally the cheapest, at the cost of additional trust assumptions."* `[S]`

A secondary source characterises poqeth's measured range as *"costs from hundreds of thousands to hundreds of millions of gas for the studied"* schemes `[S]`, but I could not retrieve the paper's own gas tables — eprint.iacr.org and dl.acm.org both returned 403 to fetch. **No poqeth MAYO gas figure is quoted anywhere in this spec, because none was read.** That is a gap, listed in §10.1.

For comparison, the only production-quality pure-EVM PQC verifier that exists is [`fireblocks-labs/evm-ml-dsa-verifier`](https://github.com/fireblocks-labs/evm-ml-dsa-verifier): **MIT** (verified by reading the LICENSE text, not by trusting the API's `NOASSERTION` label, which is a classifier artifact of the vendoring appendix), ML-DSA-44 only, 1,226,311 gas `[S]`, with 320 tests, NIST ACVP on-chain including must-reject vectors, Wycheproof, 62 Z3-proved arithmetic properties, 64 Lean 4 theorems, 50 mutation kills, and 3,432,113 bytes of ACVP ML-DSA-44 vectors under `tools/fixtures/acvp_data/mldsa44.json`.

**So the only compact non-ML-DSA on-chain verifier is unlicensed and undeployable, and the only deployable on-chain verifier is ML-DSA.** That is the actual shape of the problem.

---

## 3. The three architectures

Each resolves the §2.2 tension by giving up something different.

### A. Compact off-chain — verification never enters the EVM

Scheme: **SQIsign-L1** (148 B sig, 65 B pk) or **MAYO_2** (239 B sig, 2,928 B pk).

Attestors sign claims with a compact PQC scheme; other attestors and the sequencer verify natively in TypeScript or Rust. The bridge contract keeps its existing ECDSA quorum and stores a `keccak256` commitment to the PQC bundle. Nothing needs a precompile, a fork, or an EVM verifier.

- Gains: requirement 3 fully met — 2.31× or 3.73× ECDSA, same order of magnitude. Requirement 1 met, no ML-DSA. Requirement 2 met for MAYO; **not** met for SQIsign, whose signing runs 93.9–674.7 Mcycles on x86_64 with 7× jitter `[S]`.
- Gives up: the EVM cannot independently check a PQC signature. A compromised sequencer can post a commitment the PQC bundle does not match, and only an off-chain watcher would notice. This is the trust model `pqc-v2-helios-q.md` v0.1 rejected and v0.2 lifted.
- Cost: lowest. Node-side work only.

### B. Compact on-chain — fork Besu to add a precompile

Scheme: **FN-DSA-512** via EIP-8052 (3,000 gas) or EIP-7619 (`0x65`, 1,465 base + 6/word). Both are Draft, neither is in any released client.

- Gains: 666-byte signature verified on-chain at precompile cost — roughly 3,000 gas against ML-DSA-44's 1,226,311. Requirement 3 largely met, requirement 1 met.
- Gives up: a permanent Besu fork. Measured `[M]`: of Besu's 8,893 paths and 134 plugin service interfaces, **zero expose precompile registration**. There is no plugin route. Any validator not running the fork computes a **different state root**, which is a chain split, not a liveness fault. Every future Besu security patch becomes manual.
- Also: FIPS 206 is still in development, so the scheme can change after the fork is built. And Cloudflare's assessment is that Falcon *"is difficult to implement … in a timing side-channel secure way"* `[S]` — which is why they shipped ML-DSA. The owner's own `pqc_sidechannel_report` tool cannot check it: its enum excludes Falcon entirely `[M]`.
- Cost: highest, and irreversible.

### C. Deployable on-chain today — ML-DSA-44, pure EVM

This is the option provisionally selected in the main session and the one requirement 1 forbids.

- Gains: works on stock `besu:26.10.0` with no fork and no consensus risk. FIPS 204 final — immune to the HAWK failure mode. MIT-licensed verifier with formal methods behind it and 3.4 MB of ACVP vectors.
- Gives up: requirement 3 outright — 2,420 bytes is 37.81× ECDSA, and a claim costs 12.72% of a block. Requirement 1 outright.
- Cost: moderate, but see §6.3 — the build settings do not match LXON's and the published gas figure may not survive the translation.

### Rejected

- **UOV** — 96-byte signature, the smallest in existence, but a 67 kB-to-272 kB public key. Three of them on-chain is 3.2M gas of calldata. No EVM implementation.
- **SLH-DSA** — FIPS 205 final and a 32-byte public key, but a 7,856-byte signature and no published EVM gas figure.
- **Writing our own verifier** — `MlDsaVerifierPure.sol:11-14` already admits the full NTT plus polynomial arithmetic is ~2,000 lines. For a multivariate scheme it would mean implementing GF(31) quadratic-system evaluation plus MAYO's seed expansion from scratch, with no reference to differential-test against and no licence to read one.
- **Optimistic / naysayer verification** — poqeth's cheapest mode, and genuinely promising for a compact scheme on-chain. Rejected for now because the only implementation is UNLICENSED, it adds a dispute window and a new trust assumption to a bridge that has settled real value, and requirement 4 already spends the project's deception budget on the honeypot. Worth revisiting as a Phase 4 research item once a licensed implementation exists.

---

## 4. Current LXON state

### 4.1 Repository

All `[M]` this session.

| Finding | Evidence |
|---|---|
| The tracked PQC contracts live in `apps/contracts-helios/src/satellite/pq/` | `git ls-files \| grep satellite/pq` returns exactly 4 files, all under `apps/contracts-helios` |
| The top-level `contracts/` tree is **untracked** | `git status --porcelain contracts` → `?? contracts/`; `git ls-files contracts` → 0 files. Not gitignored — `git check-ignore` returns nothing |
| The two copies are currently byte-identical | `diff -rq contracts/src/satellite/pq apps/contracts-helios/src/satellite/pq` → exit 0 |
| `apps/contracts-helios/src` **compiles clean** | `forge build --skip test script` → exit 0, solc 0.8.26, 104 files |
| `apps/contracts-helios` **test tree does not** | `forge build` fails: `test/USDL.t.sol` cannot resolve `../../src/USDL.sol`, and `test/MainnetComplianceTest.t.sol:41` calls `ComplianceRegistry.verify`, which does not exist. Both pre-existing, neither PQC-related |
| The pure verifier is a fail-closed skeleton | `MlDsaVerifierPure.sol:72` → `return false;`, with `// TODO(allow)` at line 70 |
| The wrong ML-DSA-65 length is hardcoded in **14 files** | `grep -rl 3309` across `contracts`, `apps`, `sdk`, excluding `node_modules` and `dist`. FIPS 204 specifies **3,293** |
| Six deploy scripts import three contracts that do not exist | `DeployMLDSAVerifier.s.sol` → `MLDSAVerifier.sol` MISSING; `DeployMLDSAKeyStorage.s.sol` → `MLDSAKeyStorage.sol` MISSING; `DeployPQCContracts.s.sol` → both plus `HybridSignatureVerifier.sol` MISSING; `RegisterMLDSAKeys.s.sol`, `RegisterMLDSAKeysFromFile.s.sol` → `MLDSAKeyStorage.sol` MISSING; `ConfigureHybridMode.s.sol` → `HybridSignatureVerifier.sol` MISSING. `apps/contracts/contracts/` holds 76 `.sol` files and none of those three names |
| The PQC dependency is absent, not merely mislinked | `@noble/post-quantum` declared in `apps/lxon-blockchain/package.json:21` and `sdk/typescript/package.json:30`; the directory does not exist in `apps/lxon-blockchain`, `sdk/typescript` or `apps/contracts` |
| The precompile address collides with secp256r1 | `MlDsaVerifierPrecompile.sol:18-19` uses `0x0100`/`0x0101`. Besu `Address.java:92` assigns `0x0100` to `P256_VERIFY` (EIP-7951), registered in `MainnetPrecompiledContracts.populateForOsaka`. EIP-8051 actually specifies `0x12`/`0x13` |

The 3,309 figure is not a typo someone made up: [arXiv 2601.17785](https://arxiv.org/html/2601.17785v1) Table I prints 3,309 and 4,627, so it was most likely copied from secondary literature.

### 4.2 Chains

All `[M]` this session.

**Chain 724** — `https://rpc.lxon.in`:

- The chain was restarted from an empty volume; blocks 1–242,493 of the previous instance are gone. The block counter is therefore low and **rising from a recent zero**, which is why the reading below is small.
- `eth_blockNumber` → `0x93f` = **2,367 blocks** (re-measured 2026-11-03; an earlier read in the same session returned `0x7b3` = 1,971). **This number is perishable and must not be asserted against** — the chain is live and sealing at ~5 s, so it moves ~17,000 blocks per day. The load-bearing property is the next line, not this one.
- `eth_getCode(0x9B15fEe95995a15Da2d64D8E2958f9792D5D6a25)` → **`0x`**, re-measured at block 2,367. The v4.1 bridge does not exist on 724, and did not appear in the ~400 blocks between the two readings.
- Control: the same endpoint answered `eth_blockNumber` and `eth_getBlockByNumber` successfully in the same request batch, so the `0x` is a real empty read, not a dead node. `polygon-rpc.com` returned `"API key disabled"` and was discarded; `polygon.drpc.org` answered.
- `gasLimit` = `0x1c9c380` = **30,000,000**, re-measured from the live `latest` block header (not only from genesis files). A third genesis, `lxon-evm-node/besu/genesis.qbft.json`, says `0x59682f00` = 1,500,000,000 — inconsistent with the deployed chain and worth reconciling separately (D4).

**Chain 137** — bridge `0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95` (full address recovered from `~/.lxon/runs/list-137-claims.py`, since the runbooks carry only the `0xbDC32d8c…4A95` fragment and one of them records that reconstructing the middle produced a wrong address). Every row below was re-measured 2026-11-03 against `polygon.drpc.org` and returned the same value as the original read:

| Read | Value |
|---|---|
| `eth_getCode` length | **19,105 bytes** |
| EIP-1967 implementation slot `0x3608…2bbc` | `0x0000…0000` → **no proxy** |
| `configSealed()` | **true** |
| `everUsed()` | true |
| `paused()` | false |
| `validatorCount()` | 3 |

**Consequence, and it is load-bearing.** The live 137 bridge can be neither upgraded (no proxy) nor reconfigured directly (`configSealed`). Any PQC change to the 137 quorum path means deploying a **new** bridge and migrating escrow, through the 48-hour timelock. Since 724 has no bridge at all, there is currently no counterpart for 137 to talk to.

---

## 5. Hard constraints

1. **EIP-170: 24,576 bytes of deployed code.** Measured against it: Fireblocks' `f1600_170.hex` helper 21,622 B **fits**; `f1600_core.hex` 19,617 B **fits**; the live 137 bridge 19,105 B **fits**; `lacchain/sol-falcon-verify`'s `Falcon.sol` 71,213 B **exceeds by 46,637**. poqeth suppresses the check entirely.
2. **Chain 724 is Cancun.** Genesis sets `cancunTime: 0` with no Prague or Osaka. Stock `hyperledger/besu:26.10.0`. Anything gated on Osaka — including `P256_VERIFY` at `0x0100` — is inert.
3. **Besu has no plugin precompile hook.** 134 plugin service interfaces, zero expose precompile registration. `TransactionValidatorService` and `PluginTransactionSelector` *are* plugin-facing and can gate transaction admission, but they cannot let a contract verify a signature.
4. **Licensing.** Fireblocks ML-DSA-44: MIT, usable. poqeth MAYO: UNLICENSED, not usable. lacchain Falcon: Apache-2.0, usable but a self-declared PoC whose README says its storage-based implementation *"creates a serious vulnerability"* and which needs `allowUnlimitedContractSize`, a 500M block gas limit and a one-hour mocha timeout.
5. **One supply-chain caveat on the MIT verifier.** Fireblocks' `helpers/f1600_core.hex` (19,617 B) has **no reproducible generator** — their README states plainly that "the generator that emitted it was not preserved." It is SHA-256-pinned, and the blob that actually executes (`f1600_170.hex`) *is* rebuilt from it by `tools/build_f1600_batch.py --check` and compared byte-for-byte. It is differentially tested against `ethereum-optimism/lib-keccak` and 251 SHAKE KATs. That is behavioural evidence, not provenance, and their `docs/FORMAL_VERIFICATION.md` states the same limitation.
6. **Nothing compact is standardised.** HAWK went from NIST Round 3 advancement (2026-05-14) to withdrawal (2026-07-29) in **ten weeks**, after an attack halved its effective keysize. Any size-driven pick of a Round 3 candidate can be invalidated inside a quarter.

---

## 6. Build constraints specific to the ML-DSA-44 option

Recorded here because option C is the one with a working implementation, and its numbers do not transfer for free.

### 6.1 Vendoring surface

`src/` is six Solidity files, 164,590 B total: `Decode.sol` 60,801, `Ntt.sol` 51,001, `InvNtt.sol` 26,660, `FastKeccak170.sol` 12,766, `MLDSA44Verifier.sol` 9,962, `IMLDSAVerifier.sol` 1,742. Plus `helpers/`: two hex blobs and a README. **Only ML-DSA-44 exists — there is no `MLDSA65Verifier`.** `[M]`

### 6.2 Deployment topology

Three contracts, not one: the Keccak-f[1600] helper runtime, a public-key blob, and the verifier. The verifier calls the helper and checks it by `EXTCODEHASH` **on every call**, so substituting a different helper is rejected rather than trusted. Per-key setup is ~4.11M gas for a 20,545-byte expanded public-key blob `[S]`.

### 6.3 The build settings do not match

| Setting | Fireblocks (their published figure) | `apps/contracts-helios` | Chain 724 |
|---|---|---|---|
| solc | 0.8.30 | 0.8.26 | — |
| `evm_version` | **osaka** | unset → cancun default | **cancun** |
| `optimizer_runs` | 10,000 | 200 | — |
| `via_ir` | true | true | — |
| `ffi` | true (tests call a Python reference impl) | unset | — |

Two consequences. Their own `foundry.toml` comment says via-IR "shrink[s] the verifier runtime by 2,301 bytes", so at 200 runs the bytecode grows and may breach the 24,576-byte cap their helper already sits 2,954 bytes under. And if any source depends on an Osaka opcode, **option C's central claim — that it runs on today's EVM — is false for LXON's Cancun chain**, and the decision reverts to option B.

**No LXON-specific gas figure exists.** 1,226,311 is theirs, at their settings.

---

## 7. Open decisions

### D1 — Which architecture. BLOCKING.

The main session selected ML-DSA-44 hybrid / pure EVM (option C) on 2026-11-03. That selection was made in response to a statement that requirements 1 and 3 cannot both be met. **That statement was wrong on the size axis**, and is corrected in §2.2. The selection should be re-confirmed or withdrawn now that SQIsign-L1 (2.31×), MAYO_2 (3.73×) and UOV (1.50×) are on the table as non-ML-DSA options — none of which can be verified on-chain today, which is the trade-off.

My recommendation, for what it is worth: **option A with MAYO_2**, and revisit on-chain verification when FIPS 206 publishes or a licensed multivariate verifier appears. Reasoning: MAYO_2 meets requirement 3 at 3.73× and requirement 1 outright; MAYO's verification is quadratic-system evaluation rather than NTT, so it is the multivariate candidate least likely to be prohibitively slow natively; its 24-byte secret key is materially easier to protect in a keystore than Falcon's fixed-point sampler; and unlike SQIsign it does not carry 7× signing jitter on the block-production path. The cost is that the EVM cannot independently check the bundle — which, on a chain whose three validator keys are all plaintext files on one laptop, is a smaller marginal loss than it looks.

### D2 — Which contract root hosts the work.

`contracts/` is untracked and `apps/contracts-helios/` is tracked, with byte-identical copies of the PQC contracts in both. Fixing one and not the other is a half-fix. Decide whether `contracts/` is committed, deleted, or made a symlink, before any edit lands.

### D3 — Does `apps/contracts` need to keep building.

It currently does not, for reasons unrelated to PQC. If the PQC work is hosted in `apps/contracts-helios`, that is avoidable; if it is hosted in `apps/contracts`, the two broken test files there and the untracked WIP from other sessions become this program's problem.

### D4 — Reconcile the two 724 genesis files.

`besu/genesis.qbft.json` declares a 1,500,000,000 gas limit; `aws-freetier/genesis/genesis.qbft.json` and `besu/out/genesis.json` declare 30,000,000. The deployed chain is 30,000,000. Every percentage-of-block figure in this spec uses 30,000,000.

### D5 — The honeypot.

Requirement 4 is untouched by D1–D4 and carries into every option as specified in `pqc-v2-helios-q.md` §6. It needs its own acceptance criteria, which that section does not yet state in testable form.

---

## 8. Program phases

Phase 0 needs no decision and is correct under every option. Phase 1 is the probe that can falsify option C cheaply. Phases 2+ are blocked on D1.

**Phase 0 — make the ground true. No owner decision required.**

1. `pnpm install` in `apps/lxon-blockchain` and `sdk/typescript`; assert `require.resolve('@noble/post-quantum')` succeeds and that a keygen round-trip runs.
2. Replace `3309` with `3293` across all 14 files, and add a compile-time assertion tying the constant to FIPS 204.
3. Remove the `0x0100`/`0x0101` precompile probe, or repoint it at EIP-8051's `0x12`/`0x13` behind an Osaka gate. Either way, make the probe require a known-answer `true`, not merely a non-reverting return — the current `try/catch` at `MlDsaVerifierFactory.sol:27-37` cannot distinguish "precompile present" from "precompile present and answering garbage".
4. Delete or rewrite the six orphaned deploy scripts.
5. Resolve D2, then apply every fix to the surviving copy only.

**Phase 1 — feasibility probe, ~1 day, throwaway.**

Compile the Fireblocks verifier at `evm_version = "cancun"` and at `optimizer_runs = 200`. Record deployed bytecode size against the 24,576-byte cap and a real `forge test --gas-report` number. Outputs an answer, not code we keep. If it does not compile for Cancun or does not fit, option C is dead and D1 collapses to A or B.

**Phase 2 — verifier integration.** Blocked on D1 and Phase 1.

**Phase 3 — known-answer vectors and CI.** Blocked on D1 for vector selection. For ML-DSA-44 the vectors already exist: Fireblocks ships 3,432,113 B of ACVP data under MIT, which closes the repo's total absence of NIST KAT vectors. For MAYO, vectors come from `pqmayo.org` / the NIST Round-2 spec and must be generated locally.

**Phase 4 — off-chain signing.** Blocked on D1. Includes the keystore question: where the PQC signing key lives. It must not be this laptop, which already holds all three quorum keys as plaintext at `lxon-evm-node/besu/validators/validator-{1,2,3}.hex`.

**Phase 5 — bridge integration.** Blocked on D1 and on the §4.2 finding that 137 requires a new bridge plus a 48-hour timelock migration, and that 724 currently has no bridge at all.

**No phase deploys anything.** That was the standing instruction, and §4.2 is the reason it is the right one: the only chain with a live bridge cannot have it modified.

---

## 9. Verification strategy

Definition of done for this program, stated so that each item can fail:

1. A test asserts that a **valid** signature verifies `true`. Today all three tests in `MlDsaVerifier.t.sol` assert `assertFalse` or `assertTrue(v != address(0))`. A suite that only asserts the negative cannot detect a verifier that always returns false — which is exactly what shipped.
2. The same suite asserts that a **one-bit-flipped** signature verifies `false`, and that a valid signature under a different message verifies `false`. Without both, item 1 can be satisfied by `return true`.
3. Vectors are NIST ACVP or the scheme's own specification, and their provenance is recorded in a file next to them.
4. Gas figures come from `forge test --gas-report` on this repository's `foundry.toml`, with the settings printed alongside. No figure is quoted from a third party without its build settings attached.
5. Deployed bytecode size is printed for every contract and compared against 24,576.
6. The two pre-existing broken test files in `apps/contracts-helios/test/` are either fixed or explicitly excluded, and the exclusion is visible in CI output.

**Fix reports need a control and isolation.** Every claim of the form "X now works" must be accompanied by the opposite case still failing, run in a fresh process. This spec's own negative findings follow that rule: the empty `eth_getCode` on 724 sits next to a successful `eth_blockNumber` on the same endpoint, and the missing poqeth LICENSE sits next to Fireblocks' present one.

---

## 10. Gaps not closed

Stated plainly, because several of them bound what this spec can claim.

1. **No poqeth MAYO gas figure was read.** eprint.iacr.org and dl.acm.org both returned 403. The range "hundreds of thousands to hundreds of millions of gas" is a secondary characterisation from arXiv 2610.02435, and a fetch of that PDF did not surface the passage. **§2.4's conclusion rests on the code-size suppression in poqeth's config, which is measured, not on any gas number.**
2. **No pure-EVM gas figure exists for SQIsign, MAYO, UOV, Falcon, ML-DSA-65/87 or SLH-DSA.** The only measured number in this entire space is Fireblocks' ML-DSA-44.
3. **lacchain's Falcon verifier was never compiled here.** Running `npm install` inside a cloned external repository was correctly blocked by the session's code-execution classifier. §5's characterisation of it is structural — its config, its README, its 71,213-byte source size — and the conclusion is `[I]`, not `[M]`.
4. **UOV's public key size is unresolved**: ~67,000 B (Cloudflare) versus ~272,000 B (ScienceDirect, arXiv). Both cited. UOV is excluded either way, so this does not change any recommendation.
5. **MAYO parameter sets differ between Round 2 and Round 3.** Recorded in §2.1. This spec uses Round 3.
6. **No live-chain measurement of any PQC operation was possible.** 724 has no bridge; 137's is sealed.
7. **The 1,500,000,000-gas genesis file was not explained.** D4 records it; nothing here resolves which file is authoritative for a future redeploy.
8. **`quantum_domain_mcp` cannot assist with any compact scheme.** Its catalogue is 17 entries and contains no Round 3 additional-signature candidate — calling `pqc_algorithm_deep_dive("MAYO")` returns `"error": "Unknown: MAYO"` plus the available list `[M]`. This is the coverage limit that produced the original wrong size claim, and it will produce it again for anyone who treats that tool as authoritative.
9. **`pqc_sidechannel_report` cannot check Falcon** — its enum excludes it `[M]`. Under option B the project's own tooling cannot assess the primary scheme's side-channel exposure.

---

## Appendix A — commands behind the `[M]` tags

```bash
# 4.1 repository
git ls-files | grep -i 'satellite/pq'
git status --porcelain contracts                       # -> ?? contracts/
git check-ignore -v contracts                          # -> empty, not ignored
diff -rq contracts/src/satellite/pq apps/contracts-helios/src/satellite/pq
forge build --skip test script                         # exit 0
forge build                                            # fails in test/ only
grep -rl '3309' --include='*.sol' --include='*.ts' contracts apps sdk \
  | grep -v node_modules | grep -v '/dist/'            # 14 files
grep -rn '0x010[01]' contracts/src/satellite/pq/MlDsaVerifierPrecompile.sol

# 4.2 chains
curl -s -X POST https://rpc.lxon.in -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'      # 0x93f, perishable
curl -s -X POST https://rpc.lxon.in -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"eth_getCode",
       "params":["0x9B15fEe95995a15Da2d64D8E2958f9792D5D6a25","latest"]}'   # 0x
curl -s -X POST https://rpc.lxon.in -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"eth_getBlockByNumber",
       "params":["latest",false]}'                                          # gasLimit 0x1c9c380
cast call 0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95 'configSealed()(bool)' \
  --rpc-url https://polygon.drpc.org                                        # true
cast code 0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95 \
  --rpc-url https://polygon.drpc.org | wc -c                                # 19,105 bytes
# EIP-1967 implementation slot 0x3608...2bbc -> 0x0000...0000 (no proxy)

# 2.4 verifier landscape
curl -sL "https://api.github.com/search/repositories?q=MAYO+solidity+verifier"   # total_count 1
curl -sL "https://api.github.com/search/repositories?q=UOV+solidity+signature"   # total_count 0
curl -sL "https://api.github.com/search/repositories?q=SQIsign+solidity"         # total_count 0
curl -sL "https://api.github.com/repos/ruslan-ilesik/poqeth/contents/"           # no LICENSE
curl -sL "https://raw.githubusercontent.com/ruslan-ilesik/poqeth/main/src/mayo/Mayo.sol" | head -1
                                                                 # SPDX: UNLICENSED
curl -sL "https://raw.githubusercontent.com/ruslan-ilesik/poqeth/main/foundry.toml"
                                                                 # ignores code-size

# 6.x Fireblocks
curl -sL "https://raw.githubusercontent.com/fireblocks-labs/evm-ml-dsa-verifier/main/LICENSE"
                                                                 # MIT, 2,888 B
curl -sL "https://raw.githubusercontent.com/fireblocks-labs/evm-ml-dsa-verifier/main/foundry.toml"
curl -sL "https://api.github.com/repos/fireblocks-labs/evm-ml-dsa-verifier/git/trees/main?recursive=1"
```

**One technique worth keeping.** A pipeline hides exit codes: `forge build 2>&1 | tail -40` reports the exit status of `tail`, which is always 0. The first run of that command was reported as a successful build when the build had in fact failed. Re-run without a pipe, or read `${PIPESTATUS[0]}`.

## Appendix B — primary sources

- [NIST CSRC — PQC Standardization Process](https://csrc.nist.gov/projects/post-quantum-cryptography/post-quantum-cryptography-standardization) — FIPS 203/204/205 published 2024-08-13; FIPS 206 *in development*
- [pqmayo.org — params and times](https://pqmayo.org/params-times/) — MAYO Round-3 parameter sets
- [MAYO Round 2 specification (NIST CSRC)](https://csrc.nist.gov/csrc/media/Projects/pqc-dig-sig/documents/round-2/spec-files/mayo-spec-round2-web.pdf)
- [SQIsign Round 2 specification (NIST CSRC)](https://csrc.nist.gov/csrc/media/Projects/pqc-dig-sig/documents/round-2/spec-files/sqisign-spec-round2-web.pdf) — Table 1
- [sqisign.org](https://sqisign.org/) — signing/verification megacycles
- [ruslan-ilesik/poqeth](https://github.com/ruslan-ilesik/poqeth) — UNLICENSED; MAYO/W-OTS+/XMSS/SPHINCS+ EVM verification
- [poqeth — ePrint 2025/091](https://eprint.iacr.org/2025/091) and [ACM 10.1145/3708821.3736193](https://dl.acm.org/doi/10.1145/3708821.3736193) — both 403 to fetch
- [ethresear.ch — poqeth](https://ethresear.ch/t/poqeth-efficient-post-quantum-signature-verification-on-ethereum/21554)
- [fireblocks-labs/evm-ml-dsa-verifier](https://github.com/fireblocks-labs/evm-ml-dsa-verifier) — MIT; 1,226,311 gas; 3.4 MB ACVP vectors
- [Fireblocks — Post-Quantum Signatures on Ethereum Just Got 6.6× Cheaper](https://www.fireblocks.com/blog/post-quantum-signatures-ethereum-cheaper-gas)
- [lacchain/sol-falcon-verify](https://github.com/lacchain/sol-falcon-verify) — Apache-2.0 PoC, 71,213 B
- [besu-eth/besu](https://github.com/besu-eth/besu) — `Address.java:92`, `MainnetPrecompiledContracts.java:205-206`
- [EIP-7951 secp256r1 P256VERIFY](https://eips.ethereum.org/EIPS/eip-7951) · [EIP-8051 ML-DSA](https://eips.ethereum.org/EIPS/eip-8051) · [EIP-8355 ML-DSA](https://eips.ethereum.org/EIPS/eip-8355) · [EIP-8052 Falcon](https://ethereum-magicians.org/t/eip-8052-precompile-for-falcon-support/25860) · [EIP-7619 Falcon-512](https://eips.ethereum.org/EIPS/eip-7619) · [EIP-7885 NTT](https://eips.ethereum.org/EIPS/eip-7885)
- [NIST — Nine Candidates Advance to Round 3](https://www.nist.gov/news-events/news/2026/05/nine-candidates-advance-third-round-additional-digital-signatures-pqc) — includes the HAWK withdrawal footnote
- [Anthropic — Discovering cryptographic weaknesses with Claude](https://www.anthropic.com/research/discovering-cryptographic-weaknesses) · [ePrint 2026/1318](https://eprint.iacr.org/2026/1318)
- [Cloudflare — a look at the latest PQ signature standardization](https://blog.cloudflare.com/another-look-at-pq-signatures/) · [Why we cannot wait](https://blog.cloudflare.com/ml-dsa-will-have-to-do/)
- [FIPS 204](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.204.pdf)
- [arXiv 2609.24689 — Domain Specific PQ Signatures for Blockchains](https://arxiv.org/html/2609.24689v1) — Table 4
- [arXiv 2601.17785 — Performance Analysis of Quantum-Secure Digital Signatures](https://arxiv.org/html/2601.17785v1) — source of the erroneous 3,309
- [draft-ietf-cose-falcon-04](https://datatracker.ietf.org/doc/html/draft-ietf-cose-falcon-04)

Link status: all URLs in this file returned HTTP 200 at time of writing except the two 403s noted in §10.1 and `maynard-labs.com`, whose TLS certificate has expired.
