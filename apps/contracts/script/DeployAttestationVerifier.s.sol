// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/AttestationVerifier.sol";

contract DeployAttestationVerifier is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Attestation Verifier contract");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy AttestationVerifier
        // For MVP, use deployer as verification service
        // In production, use actual verification service address
        AttestationVerifier attestationVerifier = new AttestationVerifier(deployer);
        console.log("AttestationVerifier deployed at:", address(attestationVerifier));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("AttestationVerifier:", address(attestationVerifier));
        console.log("Verification Service (MVP):", deployer);
        console.log("Attestation Expiration: 300 seconds (5 minutes)");
        console.log("\n=== Gas Cost Estimate ===");
        console.log("Verification Cost: ~50,000 gas per attestation");
        console.log("Savings: 95-99% vs on-chain ML-DSA verification");
        console.log("\n=== Next Steps ===");
        console.log("1. Implement full verification service with signature verification");
        console.log("2. Integrate with bridge contracts");
        console.log("3. Test end-to-end flow");
    }
}
