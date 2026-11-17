// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/MLDSAVerifier.sol";

contract DeployMLDSAVerifier is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address attester = deployer; // Use deployer as initial attester
        
        console.log("Deploying ML-DSA-65 Verifier contract");
        console.log("Deployer:", deployer);
        console.log("Attester:", attester);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MLDSAVerifier with attester
        MLDSAVerifier verifier = new MLDSAVerifier(attester);
        console.log("MLDSAVerifier deployed at:", address(verifier));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("MLDSAVerifier:", address(verifier));
        console.log("Attester:", attester);
        console.log("\n=== Next Steps ===");
        console.log("1. Update LxonBridgeMultiSig to use new verifier");
        console.log("2. Deploy ML-DSA verification service");
        console.log("3. Test ML-DSA signature verification");
    }
}
