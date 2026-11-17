// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LXON.sol";
import "../contracts/LXONHardened.sol";
import "../contracts/VestingEscrow.sol";
import "../contracts/PriceOracle.sol";
import "../contracts/BridgeValidatorRegistry.sol";
import "../contracts/LxonBridge.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DeployAllLXON
 * @notice Comprehensive deployment script for complete LXON ecosystem
 * @dev Uses old deployment scripts as references and integrates all components
 */
contract DeployAllLXON is Script {
    uint256 constant CHAIN_ID = 724;
    uint256 constant TIMELOCK_DELAY = 2 days; // 48 hours
    
    // Existing contracts from .env (do not redeploy)
    address constant WETH_ADDRESS = 0x007696cdF0Bf860823126D72C8e3D52448B5285E;
    address constant LXON_ADDRESS = 0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E;
    address constant PAIR_ADDRESS = 0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7;
    address constant ROUTER_ADDRESS = 0x92F4D1236026F23967eBd213547FE18606AE8dD5;
    
    // Validators from .env
    address VALIDATOR_1;
    address VALIDATOR_2;
    address VALIDATOR_3;
    uint256 constant VALIDATOR_THRESHOLD = 2; // 2 of 3 for production

    function run() external {
        // Load addresses from .env
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        address founder = vm.envAddress("FOUNDER_ADDRESS");
        address yourWallet = vm.envAddress("YOUR_WALLET_ADDRESS");
        
        // Set validators
        VALIDATOR_1 = deployer;
        VALIDATOR_2 = founder;
        VALIDATOR_3 = yourWallet;
        
        console.log("===========================================");
        console.log("Complete LXON Ecosystem Deployment");
        console.log("===========================================");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Deployer:", deployer);
        console.log("Timelock Delay:", TIMELOCK_DELAY, "seconds");
        console.log("===========================================");
        
        vm.startBroadcast(deployerPrivateKey);

        // ========================================
        // Step 1: Deploy TimelockController
        // ========================================
        console.log("Step 1: Deploying TimelockController...");
        
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

        // ========================================
        // Step 2: Use Existing LXON Token
        // ========================================
        console.log("Step 2: Using existing LXON Token:", LXON_ADDRESS);

        // ========================================
        // Step 3: Deploy LXON Hardened
        // From DeployLXONMain.s.sol pattern
        // ========================================
        console.log("Step 3: Deploying LXON Hardened...");
        LXONHardened lxonHardened = new LXONHardened(address(timelock), TIMELOCK_DELAY);
        console.log("LXON Hardened deployed to:", address(lxonHardened));

        // ========================================
        // Step 4: Deploy Vesting Escrow
        // From DeployLXONMain.s.sol pattern
        // ========================================
        console.log("Step 4: Deploying Vesting Escrow...");
        VestingEscrow vestingEscrow = new VestingEscrow(LXON_ADDRESS);
        console.log("Vesting Escrow deployed to:", address(vestingEscrow));

        // ========================================
        // Step 5: Deploy Bridge Validator Registry
        // With security fixes (timelock integration)
        // ========================================
        console.log("Step 5: Deploying Bridge Validator Registry...");
        BridgeValidatorRegistry validatorRegistry = new BridgeValidatorRegistry();
        console.log("BridgeValidatorRegistry deployed to:", address(validatorRegistry));

        // Initialize BridgeValidatorRegistry
        address[] memory validatorAddresses = new address[](3);
        validatorAddresses[0] = VALIDATOR_1;
        validatorAddresses[1] = VALIDATOR_2;
        validatorAddresses[2] = VALIDATOR_3;
        
        validatorRegistry.initialize(
            deployer,
            validatorAddresses,
            VALIDATOR_THRESHOLD,
            address(timelock)
        );
        console.log("BridgeValidatorRegistry initialized (3 validators, threshold 2)");

        // ========================================
        // Step 6: Deploy LxonBridge
        // With security fixes (timelock integration)
        // ========================================
        console.log("Step 6: Deploying LxonBridge...");
        LxonBridge lxonBridge = new LxonBridge();
        console.log("LxonBridge deployed to:", address(lxonBridge));
        
        // Initialize LxonBridge
        lxonBridge.initialize(
            CHAIN_ID,
            address(validatorRegistry),
            address(timelock),
            WETH_ADDRESS,
            address(timelock)
        );
        console.log("LxonBridge initialized");

        // ========================================
        // Step 7: Deploy Price Oracle
        // From DeployPriceFloor.s.sol pattern
        // ========================================
        console.log("Step 7: Deploying Price Oracle...");
        PriceOracle priceOracle = new PriceOracle();
        console.log("PriceOracle deployed to:", address(priceOracle));

        // ========================================
        // Step 8: Grant Timelock Roles to Bridge Contracts
        // ========================================
        console.log("Step 8: Granting timelock roles to bridge contracts...");
        
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
        console.log("Deployment Summary");
        console.log("===========================================");
        console.log("TimelockController:", address(timelock));
        console.log("LXON Token (existing):", LXON_ADDRESS);
        console.log("LXON Hardened:", address(lxonHardened));
        console.log("Vesting Escrow:", address(vestingEscrow));
        console.log("BridgeValidatorRegistry:", address(validatorRegistry));
        console.log("LxonBridge:", address(lxonBridge));
        console.log("PriceOracle:", address(priceOracle));
        console.log("===========================================");
        console.log("Existing Contracts (Not Redeployed):");
        console.log("WETH:", WETH_ADDRESS);
        console.log("Pair:", PAIR_ADDRESS);
        console.log("Router:", ROUTER_ADDRESS);
        console.log("===========================================");
        console.log("IMPORTANT: Transfer timelock admin to multisig!");
        console.log("===========================================");
    }
}
