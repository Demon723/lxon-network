// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LXON.sol";

contract DeployLXONPolygon is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LXON token
        LXON lxon = new LXON(deployer);
        
        // Grant MINT_ROLE to deployer
        bytes32 MINT_ROLE = lxon.MINT_ROLE();
        lxon.grantRole(MINT_ROLE, deployer);
        
        // Set reserve ceiling (1B USD = 100B cents)
        lxon.updateCeiling(100000000000, bytes32(0));
        
        // Mint 10M LXON to deployer
        lxon.mint(deployer, 10000000 * 10**6, bytes32(0));
        
        vm.stopBroadcast();
        
        console.log("LXON Token deployed at:", address(lxon));
    }
}
