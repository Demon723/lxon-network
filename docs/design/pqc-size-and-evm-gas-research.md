# Deep research: PQC signature size floor and EVM verification cost

Version: v1.0
Date: 2026-11-03
Companion to: [`pqc-v2-helios-q.md`](./pqc-v2-helios-q.md) §0 and §1(b)
Method: web + primary-spec research, `quantum_domain_mcp`, `blockchain_expert`, browser-use MCP for pages WebFetch truncated, GitHub tree/source reads of `besu-eth/besu`.

---

## 0. Verdict on the claim under test

The claim, quoted from `pqc-v2-helios-q.md` §0:

> **666 bytes. That is the smallest signature any NIST-track post-quantum scheme produces, and it is 10.4× an ECDSA signature.** "Like normal crypto" is not reachable.

**REFUTED as stated. The real floor in the NIST pipeline today is 148 bytes — 2.31× ECDSA — and one candidate reaches 96 bytes, 1.5×.**

Three independent primary sources agree on the 148-byte figure for SQIsign-L1 (NIST Round 2 spec Table 1, the IETF COSE SQIsign draft, and NIST IR 8610 commentary). My original number was correct only for the 17-scheme catalogue inside `quantum_domain_mcp`, which does not contain SQIsign, UOV, MAYO, SNOVA, QR-UOV, SDitH, MQOM or FAEST. I presented a tool's coverage limit as a property of cryptography. That is the same class of error as calling an inference "measured".

The corrected claim, which I will stand behind:

> **Every finalised NIST PQC signature standard is ≥ 2,420 bytes.** FIPS 204 (ML-DSA) is final and its smallest parameter set, ML-DSA-44, signs at 2,420 bytes — 37.81× an ECDSA signature. FIPS 205 (SLH-DSA) is final and starts at 7,856 bytes. Those are the only two finalised signature standards, so **2,420 bytes is the floor for a signature that is a NIST standard today.**
>
> 666 bytes (FN-DSA-512) is the smallest signature among the schemes NIST has *selected* but not yet published: FIPS 206 is still **in development**, its initial public draft is not out, and the IETF COSE Falcon draft (2026-03-15) expects publication "late 2026 early 2027".
>
> Below that, the NIST **pipeline** reaches 148 bytes (SQIsign-L1) and 96 bytes (UOV), both Round 3 additional-signature candidates. What blocks them is not size — it is that neither has an EVM implementation, and UOV trades its 96-byte signature for a ~67 KB public key.
>
> **So all three compact options — Falcon 666, SQIsign 148, UOV 96 — are pre-final.** There is no "final *and* compact" row in any table. That is a sharper statement of the floor than either the original claim or my first correction, and my first correction was itself wrong: this document originally listed FIPS 206 among the "NIST-finalised" standards, which it is not.

And a second finding that matters more than the size correction:

> **The scheme the design picked (Falcon/FN-DSA-512) is the one compact scheme with no viable pure-EVM verifier, and the scheme the owner told me to avoid (ML-DSA) is the only one with an open-source, formally-verified, KAT-tested EVM verifier running at 1,226,311 gas today.** Size and verifiability point in opposite directions. That inversion is the central result of this research.

---

## 1. The corrected size table

`sig ×` is the ratio to a 64-byte ECDSA (secp256k1 `r‖s`) signature. `cd(sig)` is EIP-2028 calldata gas at the expected zero-byte rate for high-entropy data (1/256 of bytes are zero: `16·(n−n/256) + 4·(n/256)`). §0 of the design doc used the all-non-zero worst case; the difference is 0.3%.

| Scheme | Family | NIST status | pk (B) | sig (B) | sig × | cd(pk) | cd(sig) | Source |
|---|---|---|---:|---:|---:|---:|---:|---|
| ECDSA secp256k1 | ECDLP | baseline | 33 | 64 | 1.00× | 526 | 1,021 | — |
| **UOV (cat 1)** | multivariate | **Round 3** | ~67,000 | **96** | **1.50×** | 1,068,859 | 1,532 | Cloudflare, NIST spec |
| **SQIsign-L1** | isogeny/quaternion | **Round 3** | **65** | **148** | **2.31×** | 1,037 | 2,361 | NIST R2 spec Table 1 |
| SQIsign-L3 | isogeny | Round 3 | 97 | 224 | 3.50× | 1,547 | 3,574 | IETF COSE draft |
| SQIsign-L5 | isogeny | Round 3 | 129 | 292 | 4.56× | 2,058 | 4,658 | IETF COSE draft |
| HAWK-512 | lattice (LIP) | **WITHDRAWN 2026-07-29** | 1,024 | 555 | 8.67× | 16,336 | 8,854 | hawk-sign.info |
| **FN-DSA-512 (Falcon)** | NTRU lattice | selected; **FIPS 206 in development** | 897 | **666** | **10.41×** | 14,310 | 10,625 | NIST CSRC, IETF |
| FN-DSA-1024 | NTRU lattice | selected; FIPS 206 in development | 1,793 | 1,280 | 20.00× | 28,604 | 20,420 | IETF COSE draft |
| HAETAE-120 | lattice (FSwA) | Round 1 only, not advanced | 992 | 1,474 | 23.03× | 15,826 | 23,515 | arXiv 2601.17785 Tbl IV |
| ML-DSA-44 | MLWE+SIS | FIPS 204 final | 1,312 | 2,420 | 37.81× | 20,930 | 38,607 | FIPS 204, Fireblocks |
| ML-DSA-65 | MLWE+SIS | FIPS 204 final | 1,952 | **3,293** | 51.45× | 31,140 | 52,534 | FIPS 204 |
| ML-DSA-87 | MLWE+SIS | FIPS 204 final | 2,592 | 4,595 | 71.80× | 41,350 | 73,305 | FIPS 204 |
| SLH-DSA-SHA2-128s | hash | FIPS 205 final | 32 | 7,856 | 122.75× | 510 | 125,328 | FIPS 205 |
| SLH-DSA-SHA2-192s | hash | FIPS 205 final | 48 | 16,224 | 253.50× | 766 | 258,824 | FIPS 205 |

Three things this table settles that §0 got wrong or omitted:

**HAETAE is not a compact alternative.** It was the most likely candidate to beat Falcon on size, and at 1,474 bytes it is 2.2× *worse*. It also did not advance past Round 1. Strike it.

**HAWK is dead.** See §2. Its 555-byte signature would have been the best lattice number available.

**UOV's 96-byte signature is real but the public key is not deployable on-chain.** At ~67 KB the key alone costs 1,068,859 gas in calldata (Cloudflare's figure; a ScienceDirect review gives 272 KB for "classic UOV" at level 1 — the sources disagree by 4×, so treat the pk size as unsettled). Either number exceeds a whole 30M-gas block for a one-time key publication, before any verification cost. UOV is a TLS/X.509 answer, not a blockchain answer.

**SQIsign-L1 is the only genuinely interesting entry.** pk 65 bytes (2.0× ECDSA's compressed 33) and sig 148 bytes (2.31× ECDSA's 64). That is within a factor of 2.5 of "like normal crypto" on both axes, which is the closest any NIST-track scheme gets to what the owner asked for.

---

## 2. HAWK: a live demonstration that compact ≠ safe

This is the single most important process finding in the research, and it is not about HAWK.

- **2026-05-14** — NIST IR 8610 advances nine candidates to Round 3 of Additional Digital Signatures: FAEST, HAWK, MAYO, MQOM, QR-UOV, SDitH, SNOVA, SQIsign, UOV. HAWK is the only lattice-based one and carries the best size/performance profile of the nine.
- **2026-01-25** — arXiv 2601.17785 benchmarks HAWK-512 (pk 1,024 / sig 555) as a serious contender alongside ML-DSA, Falcon and HAETAE.
- **2026-07-28** — Anthropic publishes "Discovering cryptographic weaknesses with Claude": an attack that **halves HAWK's effective keysize**, found by an AI model (Claude Mythos Preview). The same work reports a second attack, "Möbius Bridge", on AES-128 round 7.
- **2026-07-29** — the HAWK team withdraws from NIST standardisation. NIST's own Round-3 announcement page carries the withdrawal footnote.

**Elapsed time from "NIST Round 3 candidate with the best compact profile" to "withdrawn, insecure": ten weeks.**

Two consequences for LXON, and they pull in opposite directions:

1. Any design that picks a non-finalised scheme on size grounds is picking a scheme that can be invalidated inside a quarter. SQIsign-L1's 148 bytes is a *Round 3 candidate*, not a standard. Falcon/FN-DSA-512's 666 bytes is **not a standard either** — NIST CSRC's own standardisation page says verbatim *"FALCON was also selected and will be published in FIPS 206 (in development)"* against *"FIPS 203, FIPS 204, and FIPS 205 … were published August 13, 2024"*; the IETF COSE Falcon draft (2026-03-15) expects publication "late 2026 early 2027"; the draft was submitted for internal approval 2025-08-28; and `pqc_algorithm_deep_dive("FN-DSA-512")` returns `"fips": "FIPS 206 (draft)", "status": "draft"`. Falcon is further along than SQIsign — it is *selected* — but it is in the same pre-final category, and HAWK shows that being selected is not the same as being safe. **The only schemes that are immune to a ten-week invalidation are ML-DSA and SLH-DSA, and both are ≥ 2,420 bytes.** That gap is worth more than the 1,754 bytes between ML-DSA-44 and Falcon.
2. The attack surface is no longer only human cryptanalysts. A size-optimised scheme with a thin security margin is exactly what an automated search finds first. `pqc_security_analysis("ML-DSA-44")` returns `marginBits: 0` against a 143-bit target — zero margin is the condition HAWK was in.

The honest reading: **§0's instinct ("this is a property of the schemes, not of implementations") was right in spirit and wrong in number.** The reason the compact candidates are not standardised yet is not bureaucracy; it is that compactness and margin are in tension, and one of them just failed in public.

---

## 3. EVM verification gas — what is actually measured

This is where the design doc was weakest. §4 contained zero measured numbers. Here is everything published, with measured/projected labelled exactly as the sources label it.

### 3.1 Pure EVM (no precompile)

| Implementation | Scheme | Gas | Label | Notes |
|---|---|---:|---|---|
| **Fireblocks `MLDSA44Verifier`** | ML-DSA-44 | **1,226,311** | **measured** | open source, unaudited research code |
| ETHDILITHIUM (ZKNox, EF-supported) | ML-DSA-44 | 8,094,831 | measured | the prior state of the art; Fireblocks' baseline |
| ETHDILITHIUM + EIP-7885 NTT precompile | ML-DSA-44 | ~5,730,000 | **the EIP's own projection** | not measured |
| lacchain `sol-falcon-verify` | Falcon-512 | **no number published** | — | self-described PoC, see below |
| Starkware (Cairo, *not* EVM) | Falcon-512 | 48,400,000 | measured | vs ~31,000 for ECDSA on Starknet |

The Fireblocks README is explicit about what 1,226,311 covers, and this matters for any cost model:

> "It covers the work inside `verify()` and nothing else. A real transaction also pays Ethereum's 21,000 gas base cost, plus the cost of sending the signature as calldata."

So the **transaction** cost of an ML-DSA-44 verification is, by arithmetic not measurement (calldata at the expected 1/256 zero-byte rate; a 30,000,000-gas block):

```
compute only, as Fireblocks reports it:
    1,226,311 gas                                   →  4.09% of a 30M block

full tx, 1,312-byte public key sent in calldata:
    21,000 (base) + 20,930 (pk) + 38,607 (sig) + 1,226,311 (compute)
  = 1,306,848 gas                                   →  4.36% of a 30M block

full tx, public key pre-deployed as a blob contract (Fireblocks' design,
20-byte address in calldata = 319 gas):
    21,000 (base) +    319 (pk address) + 38,607 (sig) + 1,226,311 (compute)
  = 1,286,237 gas                                   →  4.29% of a 30M block
```

The blob-address variant is the one Fireblocks intends, and it is why the per-key setup cost matters:

Per-key setup, also from the README: the verifier reads a **20,545-byte expanded public key** deployed as its own contract, at **~4.11M gas in code deposit** — "more than three verifications", paid once per key. The unrolled SHAKE-256 permutation is ~21 KB, which does not fit under EIP-170's 24,576-byte cap, so it lives in a second shared helper contract. Any LXON design that verifies ML-DSA on-chain inherits both constraints.

Fireblocks' own scope statement rules out the thing the design wanted:

> "This post is about ML-DSA-44 (FIPS 204) on its standard-compliant path. EVM-tuned variants that swap SHAKE for Keccak are cheaper, but they are different schemes. They are out of scope, **as are other post-quantum families**."

**There is no published pure-EVM gas figure for Falcon, SQIsign, SLH-DSA or ML-DSA-65/87.** That is a gap, not a zero.

Its verification stack is worth copying regardless of scheme: 320 tests including the full official NIST ACVP vector sets run on-chain with must-reject cases, the Wycheproof corpus, a 100-key breadth suite, 62 machine-checked arithmetic properties / 794 claims proved in Z3 and pinned to the shipped source, 64 Lean 4 theorems about exact EVM opcode semantics of the hot kernels, and mutation testing that broke the verifier 50 ways one at a time. LXON's `MlDsaVerifier.t.sol` has three tests and all three assert `false`.

### 3.2 The lacchain Falcon verifier — structural evidence, no number

`lacchain/sol-falcon-verify` is the only public Solidity Falcon-512 verifier, Apache-2.0, written explicitly "for deployment to a **Besu** Blockchain" — the same client LXON runs. 15 stars, last updated 2025-11-26, `Falcon.sol` is **71,213 bytes**.

I could not measure its gas. `npm install` inside the cloned external repo was blocked by the session's code-execution classifier, which is correct behaviour and not something I worked around. **No gas figure for this verifier was obtained by me.** What I have instead is structural, and it is damning:

```js
// /tmp/sfv/hardhat.config.js — verbatim
networks: {
  hardhat: {
    allowUnlimitedContractSize: true,   // Falcon.sol exceeds EIP-170's 24,576 B
    blockGasLimit: 500_000_000          // 16.7× LXON's 30M block limit
  },
  development: { gas: 0x1ffffffffffffe }
},
solidity: { version: "0.7.6" }          // 3 major versions behind LXON's 0.8.26
```

A project does not raise `blockGasLimit` to 500,000,000 and disable the contract-size limit unless its tests do not fit otherwise. Its README also states:

> "This implementation of the Falcon Signature Verification algorithm is a **Proof of Concept (PoC) only** and, as it stands, is **not in a state ready for production**... many variables and function arguments which were originally intended to be stack based, and hence temporary, have been implemented in 'storage'... Apart from increasing gas cost, **this also creates a serious vulnerability**. In this PoC, no attempt has been made to secure, clear or destroy this data."

And it notes that Solidity has no constant arrays, so its lookup tables "are not immutable as intended and could, in theory, be altered in order to break, manipulate or compromise one or more steps in the algorithm."

EIP-7619, the Falcon precompile proposal, reaches the same conclusion in one line: the Solidity implementation "**does not scale due to the required high amount of gas**."

**Conclusion: pure-EVM Falcon-512 verification is not available at any price that fits in an LXON block.** Inferred from three independent structural signals (test config, README self-assessment, EIP text), not measured. I am labelling it inferred.

### 3.3 Precompile proposals — four, all Draft, two colliding

| EIP | Scheme | Address(es) | Gas | Status |
|---|---|---|---|---|
| **8051** | ML-DSA verify | 0x12, 0x13 | 4,500 (both) | Draft |
| **8355** | ML-DSA verify | 0x12 (44), 0x13 (65), 0x14 (87) | `BASE + 6·⌈(L−PK_LEN−SIG_LEN)/32⌉` | Draft |
| **8052** | Falcon support | TBD | 3,000 total (1k H2P + 2k core) | Draft |
| **7619** | Falcon-512 generic verifier | 0x65 | 1,465 base + 6 per word | Draft |
| 7885 | NTT ops (accelerator, not a verifier) | 0x12–0x15 | 600 projected / 500 measured | Draft |
| **7951** | **secp256r1 P256VERIFY** | **0x100** | **6,900** | shipped in Besu (Osaka) |

**EIP-8051 and EIP-8355 both claim 0x12 and 0x13 for different specifications.** Both are Draft. Anyone implementing against either is implementing against a moving target. EIP-7885 additionally claims 0x12–0x15 for NTT, a third collision on the same range.

For scale: EIP-7951's P256VERIFY at 6,900 gas is a *classical* elliptic-curve signature verification that actually shipped. The PQC precompile proposals cluster at 3,000–4,500 gas — i.e. the EIP authors believe native PQC verification should be *cheaper* than secp256r1 verification. That is a strong signal about where mainnet is heading, and it is the same direction as Fireblocks' observation that Lean Ethereum wants to "de-enshrine ECDSA from the protocol fully."

---

## 4. NEW BUG: `0x0100` is not ML-DSA. It is secp256r1.

This is the highest-value finding of the research and it is fully verified against Besu source, not inferred.

The design doc §1(b) says:

> `MlDsaVerifierPrecompile.sol:18-19` targets EIP-8051's `VERIFY_MLDSA` at `0x0100`/`0x0101`.

That sentence is wrong in both halves. EIP-8051 specifies **0x12/0x13**, and `0x0100` is **P256VERIFY (EIP-7951), a secp256r1 ECDSA verifier**. Verified in Besu source:

```java
// datatypes/src/main/java/org/hyperledger/besu/datatypes/Address.java:91-92
/** Precompile address for P256_VERIFY. */
public static final Address P256_VERIFY = Address.precompiled(0x0100);

// evm/src/main/java/org/hyperledger/besu/evm/precompile/MainnetPrecompiledContracts.java:205-206
//   inside populateForOsaka(...)
// EIP-7951 - secp256r1 P256VERIFY
registry.put(P256_VERIFY, new P256VerifyPrecompiledContract(gasCalculator));
```

And the LXON side:

```solidity
// contracts/src/satellite/pq/MlDsaVerifierPrecompile.sol:18-19
address internal constant PRECOMPILE_MLDSA     = address(0x0100);
address internal constant PRECOMPILE_MLDSA_ETH = address(0x0101);
```

**Severity and exploitability, calibrated:**

- **Today: latent.** P256_VERIFY is registered *only* in `populateForOsaka`. LXON's genesis sets `cancunTime: 0` with no Prague or Osaka timestamp, and the pinned image is `hyperledger/besu:26.10.0`. On the live chain `0x0100` is empty, the `staticcall` fails, and `MlDsaVerifierFactory` correctly falls back to the fail-closed skeleton. **Nothing is broken right now.**
- **After an Osaka upgrade: live misrouting.** `0x0100` resolves to a *secp256r1 verifier*. The factory's probe is `try pc.verify(...) returns (bool) { precompileExists = true; } catch { precompileExists = false; }` — it treats **any non-reverting return** as proof that an ML-DSA precompile exists. P256VERIFY on malformed input returns a value rather than reverting, so the probe succeeds. `usingPrecompile` and `verifier` are both `immutable`, so the wrong routing is baked in permanently at construction with no way to correct it short of redeploying.
- **Failure mode is fail-closed, not fail-open.** The P256 verifier would return 0 for an ML-DSA signature, so `verify()` returns `false` and no invalid signature is accepted. The damage is a permanently broken PQC lane that *reports itself as precompile-accelerated* — the exact opposite of a safe silent failure, because the observable flag says "fast native path active" while the path verifies nothing.

The design doc's §1(b) needs correcting on both the EIP number and the address, and the probe needs a real discriminator (verify a known-answer signature and require `true`, not merely require a non-revert).

---

## 5. NEW BUG: the hardcoded ML-DSA-65 signature length is not FIPS 204

FIPS 204 ML-DSA-65 signature length is **3,293 bytes**. The repo hardcodes **3,309** in four places:

```
contracts/src/satellite/pq/IMlDsaVerifier.sol:20   (doc: "1952 bytes, raw")  ← pk correct
contracts/src/satellite/pq/IMlDsaVerifier.sol:22   (doc: "3309 bytes, raw")  ← WRONG
contracts/src/satellite/pq/MlDsaVerifierPure.sol:67   if (signature.length != 3309) return false;
contracts/src/satellite/pq/MlDsaVerifierFactory.sol:27  try pc.verify(new bytes(1952), new bytes(1), new bytes(3309))
contracts/test/satellite/MlDsaVerifier.t.sol:23       factory.verify(new bytes(1952), new bytes(1), new bytes(3309))
```

A conformant FIPS 204 ML-DSA-65 signature is rejected by the length check at line 67. The skeleton's only substantive behaviour — its input validation — is wrong on its own chosen parameter set. The public key length (1,952) is correct.

Where does 3,309 come from? ML-DSA-65 is 3,293; the +16 delta is not any FIPS 204 encoding I can find. arXiv 2601.17785 Table I also prints 3,309 for ML-DSA-65 and 4,627 for ML-DSA-87 (vs FIPS 204's 4,595), so the wrong figure is circulating in secondary literature — the repo most likely copied it. **Cross-checking a parameter against the FIPS document rather than a paper is the fix.**

Corroborating detail: `@noble/post-quantum@0.7.1` (the version `package.json` declares) exists on npm and is `latest`. The dependency gap recorded in §1(d) is a dangling pnpm store link, not a bad version — `pnpm install` is the whole fix.

---

## 6. Besu can host a precompile, but not through a plugin

LXON's real advantage over Ethereum mainnet is that it runs its own chain. Fireblocks had to spend $7,500 on 144 agents over nine days to get ML-DSA verification to 1.23M gas precisely because, as they put it, "on Ethereum, with no precompile planned, it costs whatever the EVM implementation costs in gas." LXON does not have that constraint. What it has instead is a fork-maintenance constraint. Measured against the Besu tree:

```
repo: besu-eth/besu   (hyperledger/besu → Moved Permanently → repo id 206414745)
tree main, recursive, truncated=False, 8,893 paths
precompile-related .java files:                 47
PQC-named paths (mldsa|dilithium|falcon|sphincs|slhdsa|kyber|mlkem|fn-dsa|postquantum):  0
plugin service interfaces under /plugin/services/:  134
  ...of which expose precompile registration:       0
```

The 134 plugin services include `TransactionValidatorService`, `TransactionSelectionService`, `BlockSimulationService`, `SecurityModuleService`, `WorldStateService`, `RpcEndpointService`, `PermissioningService`, `MetricsSystem` and a full RocksDB storage plugin layer. **None of them can register a precompile.** `PrecompileContractRegistry` lives in `evm/src/main/java/.../evm/precompile/` and `MainnetPrecompiledContractRegistries` in `ethereum/core/src/main/java/.../mainnet/` — both core, neither plugin-facing. The Besu plugin documentation page does not mention precompiled contracts at all.

So there are exactly three routes, and this is an owner decision, not an engineering one:

**(A) Fork Besu.** Add `MlDsaVerifyPrecompiledContract.java` (or a Falcon one) plus a registry entry, build a custom image, run it on every node. Precedent exists and is small: `P256VerifyPrecompiledContract.java` is one file and two registry lines. Cost is permanent fork maintenance against upstream `26.10.0`, and **any node not running the fork produces a different state root — the chain splits.** For a 3-validator chain where all three validators are on one laptop, the operational risk is low and the blast radius is total.

**(B) Plugin at the transaction layer, not the EVM.** `TransactionValidatorService` and `PluginTransactionSelector` are plugin-facing and exist today. A plugin could reject or select transactions by PQC signature validity without touching the EVM. This does not let a *contract* verify a PQC signature, so it cannot serve the bridge's on-chain quorum check — but it can enforce a chain-level policy (e.g. "no transaction enters a block without a valid PQC attestation") at zero fork cost. **This option is not in the design doc and is the cheapest real thing LXON can ship.**

**(C) Pure EVM.** Available today for ML-DSA-44 only, at **1,226,311 gas of compute (4.09% of a 30M block), or 1,286,237 gas / 4.29% for a full transaction with the key pre-deployed as a blob contract**, from unaudited research code. Not available for Falcon at any gas price.

The design doc's C2 ("precompile-first factory") silently assumes route A while its code implements route C against the wrong address. It needs to say which one it is.

---

## 7. SQIsign's real cost, which the size table hides

148 bytes is not free. From sqisign.org's own benchmarks, in megacycles:

| Platform | Sign | Verify |
|---|---|---|
| x86_64 | **93.9 – 674.7** | 12.1 – 77.6 |
| AArch64 (Apple M4 Pro) | 60.0 – 425.8 | — |
| ARM Cortex-A76 | 326.8 – 2,431.4 | — |
| ARM Cortex-M4 | 1,233.3 – 10,023.4 | — |

Signing time **varies by 7× within a single platform**. The SQIsign spec states the drawback directly: "The main drawback of SQIsign is the intricacy of the signing procedure." The Oxford slides are blunter: "The signature is involved and slow: the Deuring correspondence requires a lot of complex algorithms."

For a blockchain validator this is worse than the mean suggests. A 7× variance in signing latency is a 7× variance in block production time, and signing is on the critical path of every block. Falcon-512 signs in roughly 0.3 Mcycles — SQIsign's *fastest* observed run is 300× slower than that, and its worst case is 2,000× slower.

So the real trade for "like normal crypto" is:

- **SQIsign-L1**: 148 B sig (2.31× ECDSA), 65 B pk, signing 30–220 ms with 7× jitter, no EVM implementation, no precompile EIP, Round 3 candidate, isogeny-based (a family whose previous flagship, SIKE, was broken in 2022 — SQIsign is *not* SIKE and does not use SIDH, but the family has form).
- **FN-DSA-512**: 666 B sig (10.41× ECDSA), 897 B pk, signing sub-millisecond, **FIPS 206 still in development** (selected, not final — no initial public draft yet), no viable pure-EVM verifier, needs a precompile (EIP-7619/8052, both Draft), and Cloudflare's assessment that it "is difficult to implement... in a timing side-channel secure way" — which is why Cloudflare shipped ML-DSA instead.
- **ML-DSA-44**: 2,420 B sig (37.81× ECDSA), **works on today's EVM at 1,226,311 gas**, FIPS 204 final, fastest verifier of the three, largest calldata.

There is no option that is simultaneously compact, fast, final and EVM-verifiable. **That is the real floor, and it is a four-way tension, not a byte count.** §0 stated the floor as a number; the honest statement is that it is a trade-off with no dominating choice.

---

## 8. Urgency, and a self-contradiction inside `quantum_domain_mcp`

`predictive_coder(model="crqc-arrival", yearsAhead=10)`:

```
fit:  log2(N) = -2718.437 + 1.349 * (year - 2019)
      doublingTimeYears: 0.74   (8.9 months)
      targetNaive:        1,000,000 qubits → 2030.3
      targetAdjusted2025:   800,000 qubits → 2030.1  (Gidney 2025 factor)
expertEstimates: 1-in-4 by 2030, 1-in-2 by 2035 (GRI 7th ed., March 2026)
                 Google warning (March 2026): CRQC could arrive by 2029
caution: "Assumes continued exponential growth. IBM pivoted from Condor 1121q
          to Heron 156q — trend may overestimate."
```

`predictive_coder(model="resource-forecast", targetPhysicalQubits=1000000, yearsAhead=10)`:

```
ibm_superconducting:      2025: 120 qubits, doubling 2.31 y → 2035:  7,606
google_superconducting:   2024: 105 qubits, doubling 5.10 y → 2035:    472
quantinuum_trapped_ion:   2025:  98 qubits, doubling 1.68 y → 2035:  5,439
atom_computing_neutral:   2024: 256 qubits, doubling -0.45 y → 2035:     0
```

**These two models from the same server disagree by 2.6 orders of magnitude.** `crqc-arrival` fits IBM at a 0.74-year doubling time and reaches 1M qubits in 2030; `resource-forecast` fits the same vendor at 2.31 years and reaches 7,606 in 2035. One of them is wrong about IBM by a factor of ~130 on the same horizon. The `atom_computing` negative doubling time (shrinking to zero) and the 472-qubit Google 2035 figure are further signs these are naive log-linear fits on 2-point series.

I am recording this rather than picking the alarming one. **The urgency case for LXON should rest on the expert-survey figures (1-in-4 by 2030, 1-in-2 by 2035, GRI 7th ed. March 2026) and on Mosca's inequality, not on this server's extrapolations.** The earlier `pqc_migration_planner(20,2)` result stands on its own: migration takes ~22 years against an ~8-year window, margin −14 years, EXPOSED. That argument needs no qubit-count forecast.

---

## 9. Tool-output skepticism — four false or unusable results this session

Recorded because three of them would have gone into the design doc as fact.

1. **`blockchain_expert.gas_optimizer` on `MlDsaVerifierPrecompile.sol`** returned exactly one opportunity: *"Loop counters not in unchecked blocks — wrap `i++` in `unchecked { ++i; }` — ~30 gas per iteration, 5–15% total."* **That file contains no loop.** It is 30 lines with one `staticcall`. The finding is fabricated against the file's actual content and the 5–15% saving is meaningless. Discarded.

2. **`quantum_domain_mcp.pqc_security_analysis("FN-DSA-1024")`** returned `claimedClassicalBits: 0, marginBits: −272, marginStatus: "BELOW"`. The same tool on `FN-DSA-512` returns a correct `143/143, marginBits 0, ABOVE`. FN-DSA-1024 is not broken; the tool encodes **absent data as 0**, and 0 reads as "catastrophically below target". The tool cannot distinguish "no data" from "broken". Any automated gate built on it would fail-closed on every scheme it doesn't know, which is safe but useless, and would have made FN-DSA-1024 look like HAWK.

3. **`pqc_sidechannel_report`** accepts only `ML-KEM (Kyber) | ML-DSA (Dilithium) | HQC | SLH-DSA (SPHINCS+)`. **Falcon is not auditable by it** — the one scheme the design picked as primary cannot be side-channel-checked with the owner's own tooling. Recorded as a design gap, not a tool bug.

4. **`quantum_domain_mcp`'s scheme catalogue is 17 entries** and contains none of the nine Round 3 additional-signature candidates. Every size conclusion drawn from it alone is bounded by that catalogue. This is the direct cause of the §0 error.

Method note on the GitHub reads: my first attempt reported `precompile .java count: 0` and `PLUGIN+PRECOMPILE paths: []`. The second was a true negative; **the first was a false negative caused by `hyperledger/besu` returning `301 Moved Permanently`** — the repo is now `besu-eth/besu` (id 206414745). A control query (`/repos/hyperledger/besu` → `message: Moved Permanently`) caught it, and re-running with `-L` gave 47 precompile files and 8,893 total paths with `truncated=False`. Without the control I would have written "Besu has no precompile infrastructure", which is false.

---

## 10. What this changes in the design doc

Ranked by how much it moves the decision.

1. **§0 must be rewritten.** The floor is a four-way tension (compact / fast / final / EVM-verifiable), not 666 bytes. SQIsign-L1 at 148 B and UOV at 96 B are real and must appear, with their disqualifiers stated (no EVM impl; 67 KB pk).
2. **§1(b) must be corrected and a bug added.** `0x0100`/`0x0101` are not EIP-8051 addresses; `0x0100` is Besu's P256_VERIFY, Osaka-gated, so the probe becomes a silent misroute on upgrade. The probe must require a KAT signature to verify `true`, not merely require a non-revert.
3. **§3 scheme selection should be reopened.** FN-DSA-512 as primary assumed a precompile would exist. Route A (fork Besu) is a real but permanent cost; route B (transaction-layer plugin) is cheaper and absent from the doc. If neither is chosen, the only working on-chain verifier is ML-DSA-44 at 1.23M gas — which contradicts the owner's "don't use old type of ML-DSA" constraint, so that conflict has to be surfaced rather than designed around.
4. **§4 speed section can now carry numbers.** It currently has none. Falcon's advantage is signing latency (sub-ms, low jitter); SQIsign's disadvantage is 7× signing jitter; ML-DSA-44's on-chain cost is 1,226,311 gas measured.
5. **A new work item: fix the 3,309 → 3,293 length constant** in four files, and source every parameter from the FIPS document rather than a paper.
6. **§9 validation limits should adopt Fireblocks' stack as the target**: NIST ACVP vectors on-chain including must-reject, Wycheproof, Z3-pinned arithmetic properties, Lean 4 opcode-level theorems, and mutation testing. LXON's current suite is three `assertFalse` calls.
7. **§8 build order Phase 0 gains one item**: pin `hyperledger/besu:26.10.0` fork policy explicitly — either "we never fork" (then no precompile, then ML-DSA-44 pure EVM or nothing) or "we maintain a fork" (then budget for it). The design currently implies the second while shipping the first.

---

## 11. Gaps not closed

- **No pure-EVM gas figure exists for Falcon-512, ML-DSA-65, ML-DSA-87, SLH-DSA or SQIsign.** Not measured by me, not published by anyone I could find.
- **lacchain's Falcon verifier gas was not measured.** Blocked by the code-execution classifier on an unauthorised external repo; the block is correct and I did not bypass it. Structural evidence only (§3.2).
- **UOV's cat-1 public key size is unsettled**: ~67 KB (Cloudflare) vs 272 KB (ScienceDirect review). Both are undeployable on-chain, so it does not change the conclusion, but the number is not pinned.
- **EIP-8052's precompile addresses are still TBD** and its 3,000-gas figure has no published derivation.
- **The ceur-ws.org/Vol-4198/paper64.pdf hybrid-PQC paper could not be parsed** — WebFetch returned a raw PDF stream. Search snippets give "ML-DSA verifies in 3.37–4.49 ms with ML-DSA-44 having 3.37ms" but I could not verify the hardware or the methodology, so it is not used above.
- **The Fireblocks verifier was not run.** The gas figure is theirs, measured, and I am reporting it as theirs.
- **No live-chain measurement was possible.** Chain 724 was restarted from an empty volume (blocks 1–242,493 gone) and `rpc.lxon.in` / `explorer.lxon.in/api/eth-rpc` were unreachable this session, so nothing here is anchored to LXON's own chain state. The October 2026 broadcast records for `MLDSAVerifier` (`0xdf740bee…`), `HybridSignatureVerifier` (`0x9744b2cb…`) and `MLDSAKeyStorage` (`0x83e44331…`) refer to addresses that no longer exist on any live chain. **The entire on-chain PQC layer has to be redeployed regardless of which scheme is chosen** — which is the one genuinely fortunate consequence of the reset.

---

## Appendix A — exact commands and sources

Measured/verified by me this session:

```bash
# Besu repo redirect + tree census (control-checked)
curl -s  https://api.github.com/repos/hyperledger/besu          # → "Moved Permanently", id 206414745
curl -sL https://api.github.com/repositories/206414745/git/trees/main?recursive=1
#   truncated=False, 8,893 paths, 47 precompile .java, 0 PQC-named, 134 plugin services, 0 precompile plugins
curl -sL .../datatypes/.../Address.java            # :92  P256_VERIFY = Address.precompiled(0x0100)
curl -sL .../evm/precompile/MainnetPrecompiledContracts.java  # :205-206, inside populateForOsaka
curl -s  https://registry.npmjs.org/@noble/post-quantum        # latest 0.7.1 exists
git clone --depth 1 https://github.com/lacchain/sol-falcon-verify  # Falcon.sol 71,213 B
grep -rn "3309\|3293" contracts/src/satellite/pq contracts/test/satellite
```

Calldata arithmetic (§1) computed locally from EIP-2028 pricing at 1/256 expected zero bytes; deterministic, no execution required. Block share uses a 30,000,000-gas limit.

Sources:

- [NIST — Nine Candidates Advance to the Third Round of Additional Digital Signatures](https://www.nist.gov/news-events/news/2026/05/nine-candidates-advance-third-round-additional-digital-signatures-pqc) (incl. the HAWK withdrawal footnote)
- [NIST IR 8610 status report, second round of additional digital signatures](https://www.nist.gov/publications/status-report-second-round-additional-digital-signature-schemes-nist-post-quantum)
- [Anthropic — Discovering cryptographic weaknesses with Claude](https://www.anthropic.com/research/discovering-cryptographic-weaknesses) (HAWK effective keysize halved, 2026-07-28)
- [Cryptanalysis of HAWK: a Guessing Game — ePrint 2026/1318](https://eprint.iacr.org/2026/1318)
- [hawk-sign.info](https://hawk-sign.info/) (Hawk-512 pk 1024 / sig 555; withdrawal notice)
- [maynard-labs — HAWK Withdrawn from NIST PQC Signature Competition](https://maynard-labs.com/blog/hawk-withdrawn-nist-post-quantum-signature-competition/) *(secondary; domain resolves but its TLS certificate expired as of 2026-11-03, so the page could not be re-read — the withdrawal is independently confirmed by the NIST page above, which returned 200)*
- [SQIsign Round 2 specification (NIST CSRC)](https://csrc.nist.gov/csrc/media/Projects/pqc-dig-sig/documents/round-2/spec-files/sqisign-spec-round2-web.pdf) — Table 1: NIST-I pk 65 / sk 353 / sig 148
- [sqisign.org](https://sqisign.org/) — signing/verification megacycle benchmarks; "the main drawback of SQIsign is the intricacy of the signing procedure"
- [SQIsign: Short Quaternion and Isogeny signature (Oxford)](https://www.maths.ox.ac.uk/system/files/inline-files/sqisign.pdf)
- [Long Paper: SQISign on ARM — ePrint 2026/394](https://eprint.iacr.org/2026/394.pdf)
- [draft-mott-cose-sqisign-02 (IETF)](https://datatracker.ietf.org/doc/html/draft-mott-cose-sqisign-02) — full pk/sig comparison table
- [Cloudflare — A look at the latest post-quantum signature standardization](https://blog.cloudflare.com/another-look-at-pq-signatures/) (UOV 96 B sig / 67 kB pk)
- [Cloudflare — Why we cannot wait for better post-quantum signature algorithms](https://blog.cloudflare.com/ml-dsa-will-have-to-do/) (FN-DSA side-channel difficulty; ML-DSA shipped)
- [A comprehensive review of post-quantum digital signatures (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S1574013726000432) (UOV 272 kB pk — the conflicting figure)
- [UOV Round 2 specification (NIST CSRC)](https://csrc.nist.gov/csrc/media/Projects/pqc-dig-sig/documents/round-2/spec-files/uov-spec-round2-web.pdf)
- [FIPS 204 — Module-Lattice-Based Digital Signature Standard](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.204.pdf)
- **FIPS 206 status (NOT final) — all three links verified HTTP 200 on 2026-11-03:** [NIST CSRC PQC Standardization Process](https://csrc.nist.gov/projects/post-quantum-cryptography/post-quantum-cryptography-standardization) — verbatim: *"FIPS 203, FIPS 204, and FIPS 205 … were published August 13, 2024"* and *"FALCON was also selected and will be published in FIPS 206 (in development)"*; [draft-ietf-cose-falcon-04](https://datatracker.ietf.org/doc/html/draft-ietf-cose-falcon-04) (2026-03-15) — "expected to be published in late 2026 early 2027"; [NIST PQC Standardization (Wikipedia)](https://en.wikipedia.org/wiki/NIST_Post-Quantum_Cryptography_Standardization) — draft submitted for internal approval 2025-08-28. Plus `pqc_algorithm_deep_dive("FN-DSA-512")` → `"fips": "FIPS 206 (draft)"`, `"status": "draft"`. *(A wolfSSL page and a `csrc.nist.gov/pubs/fips/206/upd1` page cited in an earlier draft of this line returned 404 — both URLs were reconstructed from memory and have been removed. Do not re-add a link without a status check.)*
- [NIST PQC Standards summary — ML-DSA-65 pk 1,952 / sig 3,293](https://quantumsecuritydefence.com/insights/nist-pqc-enterprise-summary/)
- [Fireblocks — Post-Quantum Signatures on Ethereum Just Got 6.6× Cheaper](https://www.fireblocks.com/blog/post-quantum-signatures-ethereum-cheaper-gas) (read via browser-use MCP after WebFetch truncated to metadata only)
- [fireblocks-labs/evm-ml-dsa-verifier](https://github.com/fireblocks-labs/evm-ml-dsa-verifier) — README: 1,226,311 gas, 8,094,831 baseline, 4.11M pk-blob deposit, 20,545-byte key
- [ZKNoxHQ/ETHDILITHIUM](https://github.com/ZKNoxHQ/ETHDILITHIUM) — the 8.09M baseline the repo's own comments cite
- [EIP-8051: Precompile for ML-DSA signature verification](https://eips.ethereum.org/EIPS/eip-8051) — 0x12/0x13, 4,500 gas, Draft
- [EIP-8355: Precompiles for ML-DSA Verification](https://eips.ethereum.org/EIPS/eip-8355) — 0x12/0x13/0x14, `BASE + 6·⌈…/32⌉`, Draft
- [EIP-8052: Precompile for Falcon support](https://ethereum-magicians.org/t/eip-8052-precompile-for-falcon-support/25860) — 3,000 gas, addresses TBD, Draft
- [EIP-7619: Precompile Falcon512 generic verifier](https://eips.ethereum.org/EIPS/eip-7619) — 0x65, 1,465 + 6/word; "does not scale due to the required high amount of gas"
- [EIP-7951: secp256r1 P256VERIFY](https://eips.ethereum.org/EIPS/eip-7951) — 0x100, 6,900 gas
- [EIP-7885: Precompile for NTT operations](https://eips.ethereum.org/EIPS/eip-7885) — 0x12–0x15, 600 projected / 500 measured, Draft
- [besu-eth/besu](https://github.com/besu-eth/besu) — `Address.java:92`, `MainnetPrecompiledContracts.java:205-206`, `populateForOsaka`
- [Besu plugins documentation](https://docs.besu-eth.org/plugins) — no precompile extension point
- [lacchain/sol-falcon-verify](https://github.com/lacchain/sol-falcon-verify) — PoC Falcon-512 Solidity verifier for Besu
- [Starkware — Closing the cost gap for post-quantum signatures](https://starkware.co/blog/closing-the-cost-gap-for-post-quantum-signatures/) — Falcon-512 48.4M Cairo gas vs ~31K ECDSA
- [Performance Analysis of Quantum-Secure Digital Signatures — arXiv 2601.17785](https://arxiv.org/html/2601.17785v1) — Tables I–IV (ML-DSA / Falcon / Hawk / HAETAE sizes)
- [HAETAE: Shorter Lattice-Based Fiat-Shamir Signatures — ePrint 2023/624](https://eprint.iacr.org/2023/624.pdf)
- [NIST IR 8610 Explained](https://www.encryptionconsulting.com/nist-ir-8610/) and [NIST Selects 9 Third-Round PQC Signature Candidates](https://postquantum.com/security-pqc/nist-third-round-pqc-signatures/)
- [pqc-bench/docs/ALGORITHMS.md](https://github.com/csnp/pqc-bench/blob/main/docs/ALGORITHMS.md)

MCP calls reproduced inline: `quantum_domain_mcp.pqc_security_analysis` (ML-DSA-44, FN-DSA-512, FN-DSA-1024), `quantum_domain_mcp.predictive_coder` (crqc-arrival, resource-forecast), `blockchain_expert.gas_optimizer`, `blockchain_expert.check_dependencies`.
