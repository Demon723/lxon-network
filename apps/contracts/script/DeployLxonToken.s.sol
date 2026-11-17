// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/LxonToken.sol";

contract DeployLxonToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy with:
        // - admin = deployer (can grant/revoke roles later)
        // - initialHolder = deployer
        // - initialSupply = 100,000,000 LXON (6 decimals = 100,000,000,000,000)
        uint256 initialSupply = 100_000_000 * 10**6; // 100 million LXON
        
        LxonToken token = new LxonToken(
            msg.sender,     // admin
            msg.sender,     // initialHolder
            initialSupply  // 100M LXON
        );
        
        console.log("LXON Token deployed at:", address(token));
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("Total Supply:", token.totalSupply());
        console.log("Admin balance:", token.balanceOf(msg.sender));
        
        vm.stopBroadcast();
    }
}
