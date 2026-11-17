// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/LxonToken.sol";

contract DeployLxonRPC is Script {
    function run() external {
        // Use RPC endpoint with unlocked account
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        uint256 initialSupply = 100_000_000 * 10**6; // 100 million LXON
        
        LxonToken token = new LxonToken(
            msg.sender,
            msg.sender,
            initialSupply
        );
        
        console.log("LXON Token deployed at:", address(token));
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("Total Supply:", token.totalSupply());
        
        vm.stopBroadcast();
    }
}
