// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PQWrappedAssetVault} from "../contracts/wrapper/PQWrappedAssetVault.sol";
import {SecondarySignature} from "../contracts/crypto/SecondarySignature.sol";

/**
 * Deploy PQWrappedAssetVault contract with secondary signature support.
 */
contract DeployPQWrappedAssetVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address secondaryRegistry = vm.envAddress("SECONDARY_REGISTRY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        PQWrappedAssetVault vault = new PQWrappedAssetVault(secondaryRegistry);
        
        vm.stopBroadcast();
        
        console.log("PQWrappedAssetVault deployed to:", address(vault));
        console.log("SecondarySignature registry set to:", secondaryRegistry);
    }
}