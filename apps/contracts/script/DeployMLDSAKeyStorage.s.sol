// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/MLDSAKeyStorage.sol";

contract DeployMLDSAKeyStorage is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying ML-DSA-65 Key Storage contract");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MLDSAKeyStorage
        MLDSAKeyStorage keyStorage = new MLDSAKeyStorage(deployer);
        console.log("MLDSAKeyStorage deployed at:", address(keyStorage));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("MLDSAKeyStorage:", address(keyStorage));
        console.log("Owner:", deployer);
        console.log("\n=== Next Steps ===");
        console.log("1. Register validator keys using batchRegisterKeys");
        console.log("2. Update HybridSignatureVerifier to use this storage");
        console.log("3. Test key retrieval");
    }
}
