// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/MLDSAKeyStorage.sol";

contract RegisterMLDSAKeys is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // MLDSAKeyStorage address (deployed)
        address keyStorageAddress = 0x83e44331ab3798bA3F083337b8aAbE751AfB889c;
        
        // Validator addresses
        address validator1 = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27;
        address validator2 = 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3;
        address validator3 = 0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b;
        
        console.log("Registering ML-DSA-65 keys via storage contract");
        console.log("Key Storage:", keyStorageAddress);
        
        MLDSAKeyStorage keyStorage = MLDSAKeyStorage(keyStorageAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Register keys using batch registration
        // Note: Keys are 1952 bytes each, loaded from files in production
        // For this script, we use placeholder keys - replace with actual keys
        
        bytes memory key1 = new bytes(1952); // Load from validator_1_public_key.bin
        bytes memory key2 = new bytes(1952); // Load from validator_2_public_key.bin
        bytes memory key3 = new bytes(1952); // Load from validator_3_public_key.bin
        
        address[] memory validators = new address[](3);
        validators[0] = validator1;
        validators[1] = validator2;
        validators[2] = validator3;
        
        bytes[] memory publicKeys = new bytes[](3);
        publicKeys[0] = key1;
        publicKeys[1] = key2;
        publicKeys[2] = key3;
        
        keyStorage.batchRegisterKeys(validators, publicKeys);
        
        console.log("Registered 3 ML-DSA-65 keys");
        
        vm.stopBroadcast();
        
        // Verify registration
        console.log("\n=== Verification ===");
        console.log("Validator 1 registered:", keyStorage.isRegistered(validator1));
        console.log("Validator 2 registered:", keyStorage.isRegistered(validator2));
        console.log("Validator 3 registered:", keyStorage.isRegistered(validator3));
        console.log("Total validators:", keyStorage.getValidatorCount());
    }
}
