// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LXONSettlementAsset.sol";

contract DeployLXONSettlement is Script {
    uint256 constant CHAIN_ID = 724;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        //console.log("Deploying LXON Settlement Asset to Chain ID", CHAIN_ID);
        //console.log("Deployer address:", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy LXON Settlement Asset
        LXONSettlementAsset lxon = new LXONSettlementAsset(vm.addr(deployerPrivateKey));
        //console.log("LXON Settlement Asset deployed to:", address(lxon));

        vm.stopBroadcast();

        //console.log("LXON Settlement Asset Deployment Complete!");
        //console.log("Next Steps:");
        //console.log("1. Grant MINT_ROLE to 3-of-5 validator multi-sig");
        //console.log("2. Grant ORACLE_ROLE to attestation oracle");
        //console.log("3. Grant GUARDIAN_ROLE to 2-of-5 guardian multi-sig");
        //console.log("4. Engage accounting firm for first attestation");
        //console.log("5. Set initial reserve ceiling via updateCeiling()");
    }
}