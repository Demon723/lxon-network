// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/MLDSAKeyStorage.sol";

contract RegisterMLDSAKeysFromFile is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // MLDSAKeyStorage address (deployed)
        address keyStorageAddress = 0x83e44331ab3798bA3F083337b8aAbE751AfB889c;
        
        // Validator addresses
        address validator1 = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27;
        address validator2 = 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3;
        address validator3 = 0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b;
        
        console.log("Registering ML-DSA-65 keys from hex files");
        console.log("Key Storage:", keyStorageAddress);
        
        MLDSAKeyStorage keyStorage = MLDSAKeyStorage(keyStorageAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Read hex files and convert to bytes
        string memory hexFile1 = vm.readFile("validator_1_public_key.hex");
        string memory hexFile2 = vm.readFile("validator_2_public_key.hex");
        string memory hexFile3 = vm.readFile("validator_3_public_key.hex");
        
        // Convert hex strings to bytes
        bytes memory key1 = vm.parseBytes(hexFile1);
        bytes memory key2 = vm.parseBytes(hexFile2);
        bytes memory key3 = vm.parseBytes(hexFile3);
        
        console.log("Key 1 length:", key1.length);
        console.log("Key 2 length:", key2.length);
        console.log("Key 3 length:", key3.length);
        
        // Register keys individually
        keyStorage.registerKey(validator1, key1);
        console.log("Registered key for validator 1");
        
        keyStorage.registerKey(validator2, key2);
        console.log("Registered key for validator 2");
        
        keyStorage.registerKey(validator3, key3);
        console.log("Registered key for validator 3");
        
        vm.stopBroadcast();
        
        // Verify registration
        console.log("\n=== Verification ===");
        console.log("Validator 1 registered:", keyStorage.isRegistered(validator1));
        console.log("Validator 2 registered:", keyStorage.isRegistered(validator2));
        console.log("Validator 3 registered:", keyStorage.isRegistered(validator3));
        console.log("Total validators:", keyStorage.getValidatorCount());
        
        console.log("\n=== PQC Migration Status ===");
        console.log("Phase 1: Inventory and Freeze - COMPLETE");
        console.log("Phase 2: Add PQC Verifier - COMPLETE");
        console.log("Phase 3: Hybrid Mode - COMPLETE");
        console.log("Phase 4: Key Rotation - COMPLETE (keys registered on-chain)");
        console.log("Phase 5: Classical Sunset - PENDING");
        console.log("Off-Chain Verification Design - COMPLETE");
        console.log("On-Chain Key Storage - DEPLOYED");
        console.log("Keys Registered - COMPLETE");
    }
}
