// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LXON.sol";
import "../contracts/LXONHardened.sol";
import "../contracts/VestingEscrow.sol";

contract DeployLXONMain is Script {
    uint256 constant CHAIN_ID = 724;
    uint256 constant TIMELOCK_DELAY = 2 days;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        //console.log("Deploying LXON Contracts to Chain ID", CHAIN_ID);
        //console.log("Deployer address:", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy LXON Token
        LXON lxonToken = new LXON(address(vm.addr(deployerPrivateKey)));
        //console.log("LXON Token deployed to:", address(lxonToken));

        // Deploy LXON Hardened (requires governance address and timelock delay)
        address governance = vm.addr(deployerPrivateKey);
        LXONHardened lxonHardened = new LXONHardened(governance, TIMELOCK_DELAY);
        //console.log("LXON Hardened deployed to:", address(lxonHardened));

        // Deploy Vesting Escrow (requires token address)
        VestingEscrow vestingEscrow = new VestingEscrow(address(lxonToken));
        //console.log("Vesting Escrow deployed to:", address(vestingEscrow));

        vm.stopBroadcast();

        //console.log("LXON Contracts Deployment Complete!");
    }
}
