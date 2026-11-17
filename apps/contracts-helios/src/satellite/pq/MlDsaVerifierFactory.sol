// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IMlDsaVerifier} from "./IMlDsaVerifier.sol";
import {MlDsaVerifierPrecompile} from "./MlDsaVerifierPrecompile.sol";
import {MlDsaVerifierPure} from "./MlDsaVerifierPure.sol";

/**
 * MlDsaVerifierFactory
 * --------------------
 * Singleton factory that returns the cheapest working ML-DSA verifier
 * for the current chain.
 *
 * Probes the precompile once at deploy time and caches the result.
 * New chains: precompile first, pure Solidity fallback.
 */
contract MlDsaVerifierFactory {
    IMlDsaVerifier public immutable verifier;
    bool public immutable usingPrecompile;

    event VerifierSelected(address indexed verifier, bool precompile);

    constructor() {
        MlDsaVerifierPrecompile pc = new MlDsaVerifierPrecompile();

        // Probe with a known-bad signature; success means precompile exists.
        bool precompileExists = false;
        try pc.verify(new bytes(1952), new bytes(1), new bytes(3309)) returns (bool) {
            precompileExists = true;
        } catch { precompileExists = false; }

        if (precompileExists) {
            verifier = pc;
            usingPrecompile = true;
        } else {
            verifier = new MlDsaVerifierPure();
            usingPrecompile = false;
        }
        emit VerifierSelected(address(verifier), usingPrecompile);
    }

    /**
     * Convenience: verify without the caller needing to know the impl.
     */
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool) {
        return verifier.verify(publicKey, message, signature);
    }
}
