// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/LXONNativeTokenSimple.sol";

contract DeployLXONNativeToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LXONNativeToken token = new LXONNativeToken();
        
        console.log("LXONNativeToken deployed to:", address(token));
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Total Supply:", token.totalSupply());
        console.log("Owner:", token.owner());

        vm.stopBroadcast();
    }
}
