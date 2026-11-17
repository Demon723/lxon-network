// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonBridgeMultiSig.sol";

contract DeployLxonBridgeMultiSig is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Configuration parameters
        uint256 chainId = 724; // LXON chain ID
        address multiSigAttester = 0x8E5d97D117cadA19c695cd529b79d8229637dfBD; // Deployed MultiSigAttester
        address weth = 0x86a7da576852126c8421F7a25F8dE7cEDF9553C4; // WETH from .env
        address timelock = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27; // Deployer as timelock (temporary)

        // Deploy LxonBridgeMultiSig with constructor parameters
        LxonBridgeMultiSig bridge = new LxonBridgeMultiSig(
            chainId,
            multiSigAttester,
            weth,
            timelock
        );

        console.log("LxonBridgeMultiSig deployed to:", address(bridge));
        console.log("Deployment parameters:");
        console.log("  Chain ID:", chainId);
        console.log("  MultiSigAttester:", multiSigAttester);
        console.log("  WETH:", weth);
        console.log("  Timelock:", timelock);

        // Verify deployment
        uint256 chainIdVerify = bridge.chainId();
        address multiSigAttesterVerify = bridge.multiSigAttester();
        address wethVerify = bridge.weth();
        address timelockVerify = bridge.timelock();

        console.log("Verification:");
        console.log("  Chain ID:", chainIdVerify);
        console.log("  MultiSigAttester:", multiSigAttesterVerify);
        console.log("  WETH:", wethVerify);
        console.log("  Timelock:", timelockVerify);

        require(chainIdVerify == chainId, "Chain ID mismatch");
        require(multiSigAttesterVerify == multiSigAttester, "MultiSigAttester mismatch");
        require(wethVerify == weth, "WETH mismatch");
        require(timelockVerify == timelock, "Timelock mismatch");

        console.log("Deployment successful!");

        vm.stopBroadcast();
    }
}
