// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/WETH.sol";
import "../contracts/Pair.sol";
import "../contracts/Router.sol";

/**
 * @title DeployMissingInfrastructure
 * @notice Deploy WETH, Pair, and Router to complete LXON ecosystem
 * @dev Uses actual LXON token address from recent deployment
 */
contract DeployMissingInfrastructure is Script {
    uint256 constant CHAIN_ID = 724;
    
    // LXON token from recent deployment
    address constant LXON_ADDRESS = 0xc0177883C0c662870855660495C697385FE040f5;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        
        console.log("===========================================");
        console.log("Deploying Missing Infrastructure");
        console.log("===========================================");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Deployer:", deployer);
        console.log("LXON Token:", LXON_ADDRESS);
        console.log("===========================================");
        
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy WETH
        console.log("Step 1: Deploying WETH...");
        WETH9 weth = new WETH9();
        console.log("WETH deployed to:", address(weth));

        // Step 2: Deploy Pair (WETH/LXON)
        console.log("Step 2: Deploying Pair (WETH/LXON)...");
        Pair pair = new Pair(address(weth), LXON_ADDRESS);
        console.log("Pair deployed to:", address(pair));

        // Step 3: Deploy Router
        console.log("Step 3: Deploying Router...");
        Router router = new Router(address(weth), LXON_ADDRESS, address(pair));
        console.log("Router deployed to:", address(router));

        vm.stopBroadcast();

        console.log("===========================================");
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log("WETH:", address(weth));
        console.log("Pair:", address(pair));
        console.log("Router:", address(router));
        console.log("LXON Token (existing):", LXON_ADDRESS);
        console.log("===========================================");
        console.log("IMPORTANT: Update .env with new addresses!");
        console.log("===========================================");
    }
}
