// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../contracts/LxonBridge.sol";
import "../contracts/BridgeValidatorRegistry.sol";

contract DeployBridgeWithTimelock is Script {
    uint256 constant CHAIN_ID = 724;
    uint256 constant TIMELOCK_DELAY = 2 days; // 48 hours minimum for security
    uint256 constant VALIDATOR_THRESHOLD = 2; // Require 2 validators for bridge operations

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Bridge Contracts with Timelock to Chain ID", CHAIN_ID);
        console.log("Deployer address:", deployer);
        console.log("Timelock delay:", TIMELOCK_DELAY);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy TimelockController
        // Proposers: deployer (can propose)
        // Executors: deployer (can execute)
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        
        address admin = deployer; // Admin can grant/revoke roles
        
        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            admin
        );
        console.log("TimelockController deployed to:", address(timelock));

        // Step 2: Deploy BridgeValidatorRegistry
        address[] memory initialValidators = new address[](3);
        initialValidators[0] = 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27; // Deployer as validator 1
        initialValidators[1] = 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3; // Founder as validator 2
        initialValidators[2] = 0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b; // Your wallet as validator 3
        
        BridgeValidatorRegistry registry = new BridgeValidatorRegistry();
        registry.initialize(deployer, initialValidators, VALIDATOR_THRESHOLD, address(timelock));
        console.log("BridgeValidatorRegistry deployed to:", address(registry));
        
        // Step 3: Grant timelock admin role to registry
        // Timelock controller needs to be able to call admin functions
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        
        // Grant roles to deployer (temporary, should be transferred to multisig later)
        timelock.grantRole(PROPOSER_ROLE, deployer);
        timelock.grantRole(EXECUTOR_ROLE, deployer);
        timelock.grantRole(CANCELLER_ROLE, deployer);
        
        // Step 4: Deploy LxonBridge
        address wethAddress = 0x007696cdF0Bf860823126D72C8e3D52448B5285E; // Existing WETH address on LXON
        
        LxonBridge bridge = new LxonBridge();
        bridge.initialize(
            CHAIN_ID,
            address(registry),
            deployer,
            wethAddress,
            address(timelock)
        );
        console.log("LxonBridge deployed to:", address(bridge));

        // Step 5: Grant timelock admin role to bridge
        // The bridge's admin functions will go through timelock
        timelock.grantRole(PROPOSER_ROLE, address(bridge));
        timelock.grantRole(EXECUTOR_ROLE, address(bridge));
        
        // Step 6: Grant timelock admin role to registry
        timelock.grantRole(PROPOSER_ROLE, address(registry));
        timelock.grantRole(EXECUTOR_ROLE, address(registry));

        vm.stopBroadcast();

        console.log("Bridge Deployment Complete!");
        console.log("================================");
        console.log("TimelockController:", address(timelock));
        console.log("BridgeValidatorRegistry:", address(registry));
        console.log("LxonBridge:", address(bridge));
        console.log("================================");
        console.log("IMPORTANT: Transfer timelock admin roles to multisig wallet");
        console.log("Current roles granted to deployer:", deployer);
    }
}
