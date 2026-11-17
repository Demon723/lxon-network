// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LxonTokenEnhanced.sol";
import "../contracts/LXONBridgeEnhanced.sol";

/**
 * @title BridgeTimelockGating
 * @notice Covers the timelock role gap that made `token.executeTimelock` revert against
 *         the bridge. The bridge used to gate its five parameter setters on
 *         DEFAULT_ADMIN_ROLE, while the token's `executeTimelock` calls
 *         `target.call(data)` — so the caller the bridge saw was the token, which is not
 *         a bridge admin. The setters now require `msg.sender == timelock`, so the token
 *         can perform exactly the delayed parameter changes and nothing else.
 *
 *         Deliberately not covered here: addValidator/removeValidator/slashValidator are
 *         still DEFAULT_ADMIN_ROLE and are broken independently of this change (they do
 *         `IERC20(address(this))` although the bridge holds no token), so this suite
 *         avoids the staking path. See test/VerifyHighPriorityEnhancements.t.sol.
 */
contract BridgeTimelockGating is Test {
    LxonTokenEnhanced token;
    LXONBridgeEnhanced bridge;
    address admin;
    address stranger;

    function setUp() public {
        admin = address(0xA11CE);
        stranger = address(0xB0B);

        vm.startPrank(admin);
        token = new LxonTokenEnhanced(admin, admin, 100_000_000 * 1e18);
        bridge = new LXONBridgeEnhanced(address(0), address(token), address(token));
        vm.stopPrank();
    }

    /* ------------------------------ helpers ------------------------------ */

    function _scheduleAndExecute(bytes memory data) internal returns (bytes32 id) {
        vm.startPrank(admin);
        id = token.scheduleTimelock(address(bridge), data);
        skip(token.TIMELOCK_DELAY());
        token.executeTimelock(id);
        vm.stopPrank();
    }

    /* ---------------------------- construction ---------------------------- */

    function testStoresTimelock() public view {
        assertEq(address(bridge.timelock()), address(token));
    }

    function testConstructorRejectsZeroTimelock() public {
        vm.expectRevert("Zero timelock");
        new LXONBridgeEnhanced(address(0), address(0), address(token));
    }

    function testConstructorRejectsZeroToken() public {
        vm.expectRevert("Zero token");
        new LXONBridgeEnhanced(address(0), address(token), address(0));
    }

    function testStoresStakingToken() public view {
        assertEq(address(bridge.lxonToken()), address(token));
    }

    function testConstructorKeepsImmediateRoles() public view {
        assertTrue(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(bridge.hasRole(bridge.PAUSER_ROLE(), admin));
        // The timelock is a parameter-executor, not an administrator.
        assertFalse(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), address(token)));
    }

    /* ------------------------- the original failure ------------------------ */

    function testTimelockChangesMinConfirmations() public {
        assertEq(bridge.minConfirmations(), 2);

        _scheduleAndExecute(abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3)));

        assertEq(bridge.minConfirmations(), 3);
    }

    function testTimelockRejectsInvalidValue() public {
        bytes memory data = abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(0));

        vm.prank(admin);
        bytes32 id = token.scheduleTimelock(address(bridge), data);

        vm.startPrank(admin);
        skip(token.TIMELOCK_DELAY());
        // The bridge's own require still applies; the timelock surfaces the failed call.
        vm.expectRevert("LXON: TIMELOCK_EXECUTION_FAILED");
        token.executeTimelock(id);
        vm.stopPrank();

        assertEq(bridge.minConfirmations(), 2);
    }

    /* ------------------------ setters are gated -------------------------- */

    function testAdminCannotSetMinConfirmationsDirectly() public {
        vm.prank(admin);
        vm.expectRevert("Only timelock");
        bridge.setMinConfirmations(5);
    }

    function testAdminCannotSetPeerBridgeDirectly() public {
        vm.prank(admin);
        vm.expectRevert("Only timelock");
        bridge.setPeerBridge(137, address(0x123));
    }

    function testAdminCannotSetTreasuryDirectly() public {
        vm.prank(admin);
        vm.expectRevert("Only timelock");
        bridge.setTreasury(address(0x999));
    }

    function testAdminCannotSetMaxTransferAmountDirectly() public {
        vm.prank(admin);
        vm.expectRevert("Only timelock");
        bridge.setMaxTransferAmount(1);
    }

    function testAdminCannotSetPriceFeedDirectly() public {
        vm.prank(admin);
        vm.expectRevert("Only timelock");
        bridge.setPriceFeed(address(0x1));
    }

    function testStrangerCannotCallSetters() public {
        vm.prank(stranger);
        vm.expectRevert("Only timelock");
        bridge.setMinConfirmations(9);
    }

    /* ----------------------- the delay is enforced ----------------------- */

    function testExecuteBeforeDelayReverts() public {
        vm.prank(admin);
        bytes32 id = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );

        vm.prank(admin);
        vm.expectRevert("LXON: TIMELOCK_NOT_READY");
        token.executeTimelock(id);

        assertEq(bridge.minConfirmations(), 2);
    }

    function testOneSecondBeforeDeadlineStillReverts() public {
        vm.startPrank(admin);
        bytes32 id = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );
        // skip() is itself a call to the cheats contract, so it has to sit inside the
        // prank window or it eats the pending vm.prank.
        skip(token.TIMELOCK_DELAY() - 1);
        vm.expectRevert("LXON: TIMELOCK_NOT_READY");
        token.executeTimelock(id);
        vm.stopPrank();
    }

    function testCancelledOperationNeverApplies() public {
        vm.startPrank(admin);
        bytes32 id = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );
        token.cancelTimelock(id);
        skip(token.TIMELOCK_DELAY());
        vm.expectRevert("LXON: TIMELOCK_CANCELLED");
        token.executeTimelock(id);
        vm.stopPrank();

        assertEq(bridge.minConfirmations(), 2);
    }

    function testNonTimelockAdminCannotSchedule() public {
        // Read the role hashes first: calling token.TIMELOCK_ADMIN() is itself a call and
        // would consume the pending prank below.
        bytes32 role = token.TIMELOCK_ADMIN();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", stranger, role)
        );
        token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );
    }

    function testStrangerCannotExecute() public {
        bytes32 role = token.TIMELOCK_ADMIN();

        vm.startPrank(admin);
        bytes32 id = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );
        skip(token.TIMELOCK_DELAY());
        vm.stopPrank();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", stranger, role)
        );
        token.executeTimelock(id);
    }

    /* ------------------- immediate powers stay immediate ------------------ */

    function testEmergencyStopIsNotTimelocked() public {
        assertFalse(bridge.transfersPaused());

        vm.prank(admin);
        bridge.triggerCircuitBreaker(true, false, false);

        assertTrue(bridge.transfersPaused());
        assertFalse(bridge.messagesPaused());
    }

    function testRoleManagementIsNotTimelocked() public {
        bytes32 pauser = bridge.PAUSER_ROLE();
        bytes32 adminRole = bridge.DEFAULT_ADMIN_ROLE();

        assertFalse(bridge.hasRole(pauser, stranger));
        assertTrue(bridge.hasRole(adminRole, admin));

        vm.prank(admin);
        bridge.grantRole(pauser, stranger);

        assertTrue(bridge.hasRole(pauser, stranger));
    }

    function testPeerBridgeAppliesThroughTimelock() public {
        address peer = address(0xDEAD);
        _scheduleAndExecute(abi.encodeWithSignature("setPeerBridge(uint256,address)", uint256(137), peer));
        assertEq(bridge.peerBridges(137), peer);
    }

    function testTreasuryAppliesThroughTimelock() public {
        address newTreasury = address(0xFEED);
        _scheduleAndExecute(abi.encodeWithSignature("setTreasury(address)", newTreasury));
        assertEq(bridge.treasury(), newTreasury);
    }
}
