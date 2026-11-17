// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/MLDSAVerifier.sol";
import "../contracts/HybridSignatureVerifier.sol";

contract DeployPQCContracts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address attester = vm.envAddress("ATTESTER_ADDRESS");
        
        console.log("Deploying PQC contracts from:", deployer);
        console.log("Attester address:", attester);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ML-DSA-65 Verifier with attester
        MLDSAVerifier mlDsaVerifier = new MLDSAVerifier(attester);
        console.log("ML-DSA-65 Verifier deployed at:", address(mlDsaVerifier));
        
        // Deploy Hybrid Signature Verifier
        HybridSignatureVerifier hybridVerifier = new HybridSignatureVerifier(address(mlDsaVerifier));
        console.log("Hybrid Signature Verifier deployed at:", address(hybridVerifier));
        
        vm.stopBroadcast();
        
        // Log deployment details
        console.log("\n=== Deployment Summary ===");
        console.log("ML-DSA-65 Verifier:", address(mlDsaVerifier));
        console.log("Hybrid Signature Verifier:", address(hybridVerifier));
        console.log("Deployer:", deployer);
        console.log("Attester:", attester);
        
        // Verify deployment
        address deployedAttester = mlDsaVerifier.getAttester();
        console.log("\n=== Verification ===");
        console.log("Attester set correctly:", deployedAttester == attester);
        
        bool isReady = mlDsaVerifier.isProductionReady();
        console.log("Production Ready:", isReady);
        
        HybridSignatureVerifier.HybridMode mode = hybridVerifier.getCurrentMode();
        console.log("Initial Mode:", uint256(mode), "(0=CLASSICAL_ONLY, 1=HYBRID_AND, 2=PQC_ONLY)");
    }
}
