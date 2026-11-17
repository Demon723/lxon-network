// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {ValidatorKeyRegistry} from "../../contracts/governance/ValidatorKeyRegistry.sol";

contract ValidatorKeyRegistrySecondaryTest is Test {
    ValidatorKeyRegistry reg;
    address gov = address(0xA11CE);
    address v1 = address(0xB0B);

    function setUp() public {
        reg = new ValidatorKeyRegistry(gov);
        vm.prank(gov);
        reg.setSecondaryScheme(1, true); // MAYO-1
    }

    function test_secondary_disabled_by_default_in_fresh() public {
        ValidatorKeyRegistry fresh = new ValidatorKeyRegistry(gov);
        (,, uint8 scheme, bool enabled) = (
            bytes32(0), bytes32(0), fresh.secondarySchemeId(), fresh.secondaryEnabled()
        );
        assertEq(scheme, 0);
        assertFalse(enabled);
    }

    function test_secondary_rotation() public {
        bytes32 k1 = keccak256("mdsa");
        bytes32 s1 = keccak256("mayo");
        vm.startPrank(v1);
        reg.proposeRotation(k1); reg.acceptRotation();
        reg.proposeSecondaryRotation(s1); reg.acceptSecondaryRotation();
        vm.stopPrank();

        assertTrue(reg.isAuthorized(v1, k1));
        assertTrue(reg.isSecondaryAuthorized(v1, s1));
    }

    function test_force_rotate_revokes_both() public {
        bytes32 k1 = keccak256("k1"); bytes32 s1 = keccak256("s1");
        bytes32 k2 = keccak256("k2"); bytes32 s2 = keccak256("s2");
        vm.startPrank(v1);
        reg.proposeRotation(k1); reg.acceptRotation();
        reg.proposeSecondaryRotation(s1); reg.acceptSecondaryRotation();
        vm.stopPrank();

        vm.prank(gov);
        reg.forceRotate(v1, k2, s2);

        assertFalse(reg.isAuthorized(v1, k1));
        assertFalse(reg.isSecondaryAuthorized(v1, s1));
        assertTrue(reg.isAuthorized(v1, k2));
        assertTrue(reg.isSecondaryAuthorized(v1, s2));
        assertTrue(reg.revoked(k1));
        assertTrue(reg.revoked(s1));
    }
}
