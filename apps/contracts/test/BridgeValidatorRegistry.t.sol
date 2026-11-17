// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/BridgeValidatorRegistry.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract BridgeValidatorRegistryTest is Test {
    BridgeValidatorRegistry registry;
    TimelockController timelock;
    
    address deployer = address(0x1);
    address validator1 = address(0x2);
    address validator2 = address(0x3);
    address validator3 = address(0x4);
    address user = address(0x5);
    
    uint256 constant TIMELOCK_DELAY = 2 days;
    
    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy timelock
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);
        
        // Deploy registry
        address[] memory validators = new address[](3);
        validators[0] = validator1;
        validators[1] = validator2;
        validators[2] = validator3;
        registry = new BridgeValidatorRegistry();
        registry.initialize(deployer, validators, 2, address(timelock));
        
        // Grant timelock roles
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        timelock.grantRole(PROPOSER_ROLE, address(registry));
        timelock.grantRole(EXECUTOR_ROLE, address(registry));
        
        vm.stopPrank();
    }
    
    function testInitialize() public view {
        assertEq(registry.admin(), deployer);
        assertEq(registry.threshold(), 2);
        assertEq(registry.isValidator(validator1), true);
        assertEq(registry.isValidator(validator2), true);
        assertEq(registry.isValidator(validator3), true);
    }
    
    function testAddValidator() public {
        vm.startPrank(address(timelock));
        registry.addValidator(user);
        assertEq(registry.isValidator(user), true);
        vm.stopPrank();
    }
    
    function testRemoveValidator() public {
        vm.startPrank(address(timelock));
        registry.removeValidator(validator3);
        assertEq(registry.isValidator(validator3), false);
        vm.stopPrank();
    }
    
    function testSetThreshold() public {
        vm.startPrank(address(timelock));
        registry.setThreshold(3);
        assertEq(registry.threshold(), 3);
        vm.stopPrank();
    }
    
    function testAttestationDigest() public view {
        bytes32 digest = registry.attestationDigest(
            724,
            725,
            address(this),
            keccak256("transferId"),
            address(0x6),
            100 ether,
            user
        );
        // Just verify the digest is computed (not zero)
        assertTrue(digest != bytes32(0));
    }
    
    function testIncrementTransferNonce() public {
        bytes32 transferId = keccak256("test");
        vm.startPrank(address(timelock));
        registry.incrementTransferNonce(transferId);
        assertEq(registry.transferNonces(transferId), 1);
        vm.stopPrank();
    }
    
    function testOnlyAdmin() public {
        vm.startPrank(user);
        vm.expectRevert("REG: FORBIDDEN");
        registry.addValidator(user);
        vm.stopPrank();
    }
}
