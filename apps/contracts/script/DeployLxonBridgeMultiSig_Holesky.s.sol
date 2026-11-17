// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonBridgeMultiSig.sol";

contract DeployLxonBridgeMultiSig_Holesky is Script {
    function run() external {
        uint256 chainId = 17000; // Holesky Testnet
        address multiSigAttester = 0x8E5d97D117cadA19c695cd529b79d8229637dfBD; // LXON MultiSigAttester
        address weth = 0x9c3c9283D5E3d0f4Ab4EE0a00790089629476f76; // WETH on Holesky
        address timelock = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27; // Deployer as timelock

        vm.startBroadcast();

        LxonBridgeMultiSig bridge = new LxonBridgeMultiSig(
            chainId,
            multiSigAttester,
            weth,
            timelock
        );

        console.log("LxonBridgeMultiSig deployed on Holesky Testnet");
        console.log("Address:", address(bridge));
        console.log("Chain ID:", chainId);
        console.log("MultiSigAttester:", multiSigAttester);
        console.log("WETH:", weth);
        console.log("Timelock:", timelock);

        vm.stopBroadcast();
    }
}
