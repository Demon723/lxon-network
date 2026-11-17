// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ValidatorKeyRegistry} from "../contracts/governance/ValidatorKeyRegistry.sol";

/**
 * Deploy ValidatorKeyRegistry contract with secondary pubkey support.
 */
contract DeployValidatorKeyRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ValidatorKeyRegistry registry = new ValidatorKeyRegistry(governance);
        
        vm.stopBroadcast();
        
        console.log("ValidatorKeyRegistry deployed to:", address(registry));
        console.log("Governance set to:", governance);
    }
}