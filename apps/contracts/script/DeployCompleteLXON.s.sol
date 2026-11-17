// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LXON.sol";
import "../contracts/LXONHardened.sol";
import "../contracts/VestingEscrow.sol";
import "../contracts/WETH.sol";
import "../contracts/Pair.sol";
import "../contracts/Router.sol";
import "../contracts/PriceOracle.sol";
import "../contracts/LxonBridge.sol";
import "../contracts/BridgeValidatorRegistry.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DeployCompleteLXON
 * @notice Complete deployment script for LXON ecosystem including timelock governance
 * @dev References old deployment patterns from DeployLXONMain.s.sol and existing deployment configs
 */
contract DeployCompleteLXON is Script {
    uint256 constant CHAIN_ID = 724;
    uint256 constant TIMELOCK_DELAY = 2 days; // 48 hours as per security requirements
    
    // WETH address from existing deployment (keep this as it's already deployed)
    address constant WETH_ADDRESS = 0x007696cdF0Bf860823126D72C8e3D52448B5285E;
    
    // Validators from .env configuration
    address VALIDATOR_1;
    address VALIDATOR_2;
    address VALIDATOR_3;
    uint256 VALIDATOR_THRESHOLD;

    function run() external {
        // Use production deployer from .env
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        
        // Use production addresses from .env
        VALIDATOR_1 = deployer; // Use deployer as validator 1
        VALIDATOR_2 = vm.envAddress("FOUNDER_ADDRESS"); // Use founder as validator 2
        VALIDATOR_3 = vm.envAddress("YOUR_WALLET_ADDRESS"); // Use your wallet as validator 3
        VALIDATOR_THRESHOLD = 2; // Production threshold: 2 of 3
        
        console.log("Deploying Complete LXON Ecosystem to Chain ID", CHAIN_ID);
        console.log("Deployer address:", deployer);
        console.log("Validator 1:", VALIDATOR_1);
        console.log("Validator 2:", VALIDATOR_2);
        console.log("Validator 3:", VALIDATOR_3);
        console.log("Timelock delay:", TIMELOCK_DELAY, "seconds");
        
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy TimelockController (Governance)
        // Following pattern from DeployLXONMain.s.sol which uses Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        
        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer // admin
        );
        console.log("TimelockController deployed to:", address(timelock));

        // Step 2: Use existing LXON Token from .env (already deployed)
        // From old deployment: 0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E
        address lxonChangeToken = vm.envAddress("LXON_ADDRESS");
        console.log("Using existing LXON Token:", lxonChangeToken);

        // Step 3: Deploy Bridge Validator Registry
        // NEW: Security fix - timelock integration
        BridgeValidatorRegistry validatorRegistry = new BridgeValidatorRegistry();
        console.log("BridgeValidatorRegistry deployed to:", address(validatorRegistry));

        // Step 4: Initialize BridgeValidatorRegistry
        address[] memory validatorAddresses = new address[](3);
        validatorAddresses[0] = VALIDATOR_1;
        validatorAddresses[1] = VALIDATOR_2;
        validatorAddresses[2] = VALIDATOR_3;
        
        validatorRegistry.initialize(
            deployer,
            validatorAddresses,
            VALIDATOR_THRESHOLD, // threshold of 2 for production (2 of 3)
            address(timelock)
        );
        console.log("BridgeValidatorRegistry initialized (3 validators, threshold 2)");

        // Step 5: Deploy LxonBridge
        // NEW: Security fix - timelock integration
        LxonBridge lxonBridge = new LxonBridge();
        console.log("LxonBridge deployed to:", address(lxonBridge));
        
        // Step 6: Initialize LxonBridge
        lxonBridge.initialize(
            CHAIN_ID,
            address(validatorRegistry),
            address(timelock),
            WETH_ADDRESS,
            address(timelock)
        );
        console.log("LxonBridge initialized");

        // Step 7: Deploy Price Oracle (if needed)
        // From old deployment patterns
        PriceOracle priceOracle = new PriceOracle();
        console.log("PriceOracle deployed to:", address(priceOracle));

        // Step 8: Grant Timelock Roles to Bridge Contracts
        // Following OpenZeppelin TimelockController pattern
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        
        timelock.grantRole(PROPOSER_ROLE, address(lxonBridge));
        timelock.grantRole(EXECUTOR_ROLE, address(lxonBridge));
        timelock.grantRole(CANCELLER_ROLE, address(lxonBridge));
        
        timelock.grantRole(PROPOSER_ROLE, address(validatorRegistry));
        timelock.grantRole(EXECUTOR_ROLE, address(validatorRegistry));
        timelock.grantRole(CANCELLER_ROLE, address(validatorRegistry));
        
        console.log("Timelock roles granted to bridge contracts");

        vm.stopBroadcast();

        console.log("===========================================");
        console.log("Complete LXON Deployment Summary");
        console.log("===========================================");
        console.log("TimelockController:", address(timelock));
        console.log("LXON Token (existing):", lxonChangeToken);
        console.log("BridgeValidatorRegistry:", address(validatorRegistry));
        console.log("LxonBridge:", address(lxonBridge));
        console.log("PriceOracle:", address(priceOracle));
        console.log("===========================================");
        console.log("IMPORTANT: Transfer timelock admin to multisig!");
        console.log("Current timelock admin:", deployer);
        console.log("===========================================");
    }
}
