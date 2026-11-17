// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/HybridSignatureVerifier.sol";

contract ConfigureHybridMode is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Hybrid verifier address from deployment
        address hybridVerifierAddress = 0x9744B2CbD83AD1a1BA2B02fE2158624e2f8AB7D0;
        
        // Validator addresses (from Phase 1 inventory)
        address validator1 = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27;
        address validator2 = 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3;
        address validator3 = 0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b;
        
        console.log("Configuring hybrid mode for validators");
        console.log("Hybrid Verifier:", hybridVerifierAddress);
        console.log("Validator 1:", validator1);
        console.log("Validator 2:", validator2);
        console.log("Validator 3:", validator3);
        
        HybridSignatureVerifier hybridVerifier = HybridSignatureVerifier(hybridVerifierAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Register dummy ML-DSA public keys for each validator
        // In production, these would be real ML-DSA-65 public keys (2420 bytes each)
        bytes memory dummyPublicKey1 = new bytes(2420);
        bytes memory dummyPublicKey2 = new bytes(2420);
        bytes memory dummyPublicKey3 = new bytes(2420);
        
        hybridVerifier.registerMLDSAPublicKey(validator1, dummyPublicKey1);
        console.log("Registered ML-DSA public key for validator 1");
        
        hybridVerifier.registerMLDSAPublicKey(validator2, dummyPublicKey2);
        console.log("Registered ML-DSA public key for validator 2");
        
        hybridVerifier.registerMLDSAPublicKey(validator3, dummyPublicKey3);
        console.log("Registered ML-DSA public key for validator 3");
        
        // Transition to HYBRID_AND mode
        hybridVerifier.transitionMode(HybridSignatureVerifier.HybridMode.HYBRID_AND);
        console.log("Transitioned to HYBRID_AND mode");
        
        vm.stopBroadcast();
        
        // Verify configuration
        HybridSignatureVerifier.HybridMode mode = hybridVerifier.getCurrentMode();
        console.log("\n=== Configuration Summary ===");
        console.log("Current Mode:", uint256(mode));
        console.log("Validator 1 has PQC key:", hybridVerifier.hasMLDSAPublicKey(validator1));
        console.log("Validator 2 has PQC key:", hybridVerifier.hasMLDSAPublicKey(validator2));
        console.log("Validator 3 has PQC key:", hybridVerifier.hasMLDSAPublicKey(validator3));
        
        console.log("\n=== PQC Migration Status ===");
        console.log("Phase 1: Inventory and Freeze - COMPLETE");
        console.log("Phase 2: Add PQC Verifier - COMPLETE");
        console.log("Phase 3: Hybrid Mode - COMPLETE");
        console.log("Phase 4: Key Rotation - PENDING (need real ML-DSA keys)");
        console.log("Phase 5: Classical Sunset - PENDING");
    }
}
