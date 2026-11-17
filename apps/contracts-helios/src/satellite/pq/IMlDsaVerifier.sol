// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * IMlDsaVerifier
 * --------------
 * Standard interface for on-chain ML-DSA signature verification.
 *
 * Two implementations are provided:
 *   1. MlDsaVerifierPrecompile — calls EIP-8051's VERIFY_MLDSA precompile
 *      at 0x00...0100 when the chain supports it.
 *   2. MlDsaVerifierPure — pure Solidity fallback using the NTT-based
 *      verifier derived from ZKNoxHQ/ETHDILITHIUM (gas cost ~4.9M–8.1M).
 *
 * Callers should use `MlDsaVerifierFactory.get()` which auto-selects the
 * cheapest available implementation at runtime.
 */
interface IMlDsaVerifier {
    /**
     * @param publicKey  ML-DSA-65 public key (1952 bytes, raw)
     * @param message    Message that was signed
     * @param signature  ML-DSA-65 signature (3309 bytes, raw)
     * @return valid     True if the signature verifies against the message
     */
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);

    /** FIPS-204 variant identifier (for logging / metrics). */
    function variant() external pure returns (string memory);
}
