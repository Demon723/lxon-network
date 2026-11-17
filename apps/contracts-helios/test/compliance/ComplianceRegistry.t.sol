// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {ComplianceRegistry} from "../../src/compliance/ComplianceRegistry.sol";

contract ComplianceRegistryTest is Test {
    ComplianceRegistry reg;
    address provider = address(0xABCDEF);
    address alice = address(0xA11CE);

    function setUp() public {
        reg = new ComplianceRegistry();
        reg.setProvider(provider, true);
    }

    function test_unverified_under_threshold_ok() public view {
        assertTrue(reg.canWrap(alice, 100 ether));
    }

    function test_unverified_over_threshold_blocked() public view {
        assertFalse(reg.canWrap(alice, 10_000 ether));
    }

    function test_verified_over_threshold_ok() public {
        vm.prank(provider);
        reg.setVerified(alice, ComplianceRegistry.Tier.Basic, 840, uint64(block.timestamp + 365 days), keccak256("kyc"));
        assertTrue(reg.canWrap(alice, 10_000 ether));
    }

    function test_blocked_user_rejected() public {
        vm.prank(provider);
        reg.block_(alice, "sanctions");
        assertFalse(reg.canWrap(alice, 100 ether));
    }

    function test_expired_verification_rejected() public {
        vm.prank(provider);
        reg.setVerified(alice, ComplianceRegistry.Tier.Basic, 840, uint64(block.timestamp + 1), keccak256("kyc"));
        vm.warp(block.timestamp + 2);
        assertFalse(reg.canWrap(alice, 10_000 ether));
    }
}
