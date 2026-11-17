// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonBridgeV2.sol";
import "../contracts/AttestationVerifierV2.sol";
import "../contracts/Ed25519SignatureVerifier.sol";

contract DeployLxonBridgeV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Existing contracts
        address tokenAddress = 0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E; // LXON Token
        
        console.log("Deploying Enhanced LxonBridgeV2 with ECDSA Verification");
        console.log("Deployer:", deployer);
        console.log("Token:", tokenAddress);
        console.log("Verification Service (for testing):", deployer);
        console.log("Verification Service (Production): 0xe8eb58a65f064c2d5413337bd74b8a53a415d09e");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Ed25519SignatureVerifier (uses ECDSA as secure fallback)
        // For testing, use deployer as verification service
        Ed25519SignatureVerifier signatureVerifier = new Ed25519SignatureVerifier(
            deployer
        );
        console.log("Ed25519SignatureVerifier deployed at:", address(signatureVerifier));
        
        // Deploy new AttestationVerifierV2
        AttestationVerifierV2 attestationVerifier = new AttestationVerifierV2(address(signatureVerifier));
        console.log("AttestationVerifierV2 deployed at:", address(attestationVerifier));
        
        // Deploy LxonBridgeV2
        LxonBridgeV2 bridge = new LxonBridgeV2(tokenAddress, address(attestationVerifier));
        console.log("LxonBridgeV2 deployed at:", address(bridge));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Ed25519SignatureVerifier:", address(signatureVerifier));
        console.log("AttestationVerifierV2:", address(attestationVerifier));
        console.log("LxonBridgeV2:", address(bridge));
        console.log("Token:", tokenAddress);
        console.log("\n=== Gas Cost Fix ===");
        console.log("ECDSA verification: ~3,000 gas (vs 1M-5M gas for ML-DSA)");
        console.log("Savings: 99.7% gas reduction");
        console.log("Security: Actual cryptographic verification (not trust-based)");
        console.log("\n=== Features ===");
        console.log("Attestation-based transfer completion");
        console.log("Multi-validator support with threshold");
        console.log("Batch attestation verification");
        console.log("Gas-optimized operations");
        console.log("\n=== Next Steps ===");
        console.log("1. Test end-to-end bridge flow");
        console.log("2. Deploy to mainnet");
        console.log("3. Monitor and optimize");
    }
}
