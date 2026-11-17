// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IMlDsaVerifier} from "./IMlDsaVerifier.sol";

/**
 * MlDsaVerifierPrecompile
 * -----------------------
 * Uses EIP-8051's VERIFY_MLDSA precompile when available.
 *
 * EIP-8051 defines two precompiles at a chain-defined address (expected
 * 0x00...0100 and 0x00...0101). This contract probes the precompile on
 * first use; if the call reverts or returns malformed data, it falls
 * back to the pure Solidity verifier.
 *
 * Reference: https://eips.ethereum.org/EIPS/eip-8051
 */
contract MlDsaVerifierPrecompile is IMlDsaVerifier {
    address internal constant PRECOMPILE_MLDSA     = address(0x0100);
    address internal constant PRECOMPILE_MLDSA_ETH = address(0x0101);

    /// Encoded input: pubKey || message || signature (no length prefixes).
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view override returns (bool valid) {
        bytes memory input = abi.encodePacked(publicKey, message, signature);

        (bool ok, bytes memory out) = PRECOMPILE_MLDSA.staticcall(input);
        if (ok && out.length >= 32) {
            return abi.decode(out, (uint256)) == 1;
        }
        // Precompile not available — revert so factory can fall back.
        revert("MLDSA precompile unavailable");
    }

    function variant() external pure override returns (string memory) {
        return "ML-DSA-65-precompile";
    }
}
