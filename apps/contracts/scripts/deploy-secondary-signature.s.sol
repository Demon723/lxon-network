// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SecondarySignature} from "../contracts/crypto/SecondarySignature.sol";

/**
 * Deploy SecondarySignature contract for managing secondary PQ signature attestations.
 */
contract DeploySecondarySignature is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        SecondarySignature secondary = new SecondarySignature(governance);
        
        vm.stopBroadcast();
        
        console.log("SecondarySignature deployed to:", address(secondary));
        console.log("Governance set to:", governance);
    }
}