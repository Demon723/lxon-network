// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LxonTokenEnhanced.sol";
import "../contracts/LXONBridgeEnhanced.sol";

/**
 * @title VerifyHighPriorityEnhancements
 * @notice Verification script for high-priority security and gas optimizations
 * 
 * Tests:
 * 1. Timelock operations (48-hour delay)
 * 2. ERC2612 Permit (gasless approvals)
 * 3. Multi-sig validator signatures (threshold-based)
 */
contract VerifyHighPriorityEnhancements is Test {
    // OpenZeppelin 5.x dropped the public PERMIT_TYPEHASH constant (the typehash is derived
    // inside EIP712), so tests sign against the canonical EIP-2612 value.
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /* --------------------------- helpers --------------------------- */

    /// @notice Schedule a call on the bridge, wait out the 48h delay, execute it.
    function _timelockCall(bytes memory data) internal {
        vm.startPrank(admin);
        bytes32 id = token.scheduleTimelock(address(bridge), data);
        skip(token.TIMELOCK_DELAY());
        token.executeTimelock(id);
        vm.stopPrank();
    }

    LxonTokenEnhanced token;
    LXONBridgeEnhanced bridge;
    address admin;
    address validator1;
    address validator2;
    address validator3;
    address user;

    function setUp() public {
        admin = address(0x1);
        validator1 = address(0x2);
        validator2 = address(0x3);
        validator3 = address(0x4);
        // The permit tests sign with the standard anvil key 0, so `user` has to be its
        // address or `token.permit` recovers the wrong owner and reverts.
        user = vm.addr(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        vm.startPrank(admin);

        // Deploy token (18 decimals, 100M LXON)
        token = new LxonTokenEnhanced(admin, admin, 100_000_000 * 1e18);

        // Deploy bridge; the token is both the timelock for parameter setters and the
        // staking asset for validators.
        bridge = new LXONBridgeEnhanced(address(0), address(token), address(token));

        // Set up bridge as minter/burner
        token.grantRole(token.MINTER_ROLE(), address(bridge));
        token.grantRole(token.BURNER_ROLE(), address(bridge));

        // Mint tokens to user for testing
        token.transfer(user, 10_000 * 1e18);

        // addValidator debits the stake from msg.sender, so the admin has to approve first.
        token.approve(address(bridge), 3 * bridge.MIN_VALIDATOR_STAKE());
        bridge.addValidator(validator1, bridge.MIN_VALIDATOR_STAKE());
        bridge.addValidator(validator2, bridge.MIN_VALIDATOR_STAKE());
        bridge.addValidator(validator3, bridge.MIN_VALIDATOR_STAKE());

        // minConfirmations defaults to 2, which matches the two-signature tests below.

        vm.stopPrank();
    }

    /* --------------------------- Test 1: Timelock --------------------------- */

    function testTimelockDelay() public {
        vm.startPrank(admin);

        // Schedule a timelock operation
        bytes memory setData = abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(5));
        bytes32 timelockId = token.scheduleTimelock(address(bridge), setData);

        // Try to execute immediately - should fail
        vm.expectRevert("LXON: TIMELOCK_NOT_READY");
        token.executeTimelock(timelockId);

        // Fast-forward 48 hours
        skip(48 hours);

        // Now it should succeed
        token.executeTimelock(timelockId);

        // Verify the operation was executed
        assertEq(bridge.minConfirmations(), 5);

        vm.stopPrank();
    }

    function testTimelockCancellation() public {
        vm.startPrank(admin);

        bytes memory setData = abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(5));
        bytes32 timelockId = token.scheduleTimelock(address(bridge), setData);

        // Cancel the timelock
        token.cancelTimelock(timelockId);

        // Fast-forward 48 hours
        skip(48 hours);

        // Try to execute - should fail (cancelled)
        vm.expectRevert("LXON: TIMELOCK_CANCELLED");
        token.executeTimelock(timelockId);

        vm.stopPrank();
    }

    /* --------------------------- Test 2: ERC2612 Permit --------------------------- */

    function testPermitGaslessApproval() public {
        vm.startPrank(user);

        uint256 amount = 1000 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;

        // Get nonce
        uint256 nonce = token.nonces(user);

        // Sign permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(bridge),
                            amount,
                            nonce,
                            deadline
                        )
                    )
                )
            )
        );

        // User approves via permit (gasless)
        token.permit(user, address(bridge), amount, deadline, v, r, s);

        // Verify allowance was set
        assertEq(token.allowance(user, address(bridge)), amount);

        vm.stopPrank();
    }

    function testPermitInvalidSignature() public {
        vm.startPrank(user);

        uint256 amount = 1000 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;

        // Invalid signature
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        // Should fail with invalid signature
        vm.expectRevert();
        token.permit(user, address(bridge), amount, deadline, v, r, s);

        vm.stopPrank();
    }

    /* --------------------------- Test 3: Multi-sig Validator Signatures --------------------------- */

    function testMultiSigValidatorSignatures() public {
        // Register peer bridge through the timelock (setters are timelock-gated now).
        _timelockCall(abi.encodeWithSignature("setPeerBridge(uint256,address)", uint256(137), address(0x123)));

        vm.startPrank(user);

        token.approve(address(bridge), 1000 * 1e18);

        bytes32 transferId = bridge.initiateTransfer(
            address(token),
            1000 * 1e18,
            137,
            validator1
        );

        vm.stopPrank();

        // Validator 1 signs
        vm.startPrank(validator1);
        bridge.signTransfer(transferId);
        assertEq(bridge.getSignatureCount(transferId), 1);
        vm.stopPrank();

        // Validator 2 signs - should execute (threshold = 2)
        vm.startPrank(validator2);
        bridge.signTransfer(transferId);
        assertEq(bridge.getSignatureCount(transferId), 2);
        vm.stopPrank();

        // Verify transfer was executed
        assertEq(token.balanceOf(validator1), 1000 * 1e18);
        // Enums need an explicit cast; assertEq has no overload for them.
        assertEq(
            uint256(uint8(bridge.getTransfer(transferId).status)),
            uint256(uint8(LXONBridgeEnhanced.TransferStatus.Completed))
        );
    }

    function testMultiSigThresholdNotMet() public {
        _timelockCall(abi.encodeWithSignature("setPeerBridge(uint256,address)", uint256(137), address(0x123)));
        // Require 3 signatures
        _timelockCall(abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3)));

        vm.startPrank(user);

        token.approve(address(bridge), 1000 * 1e18);

        bytes32 transferId = bridge.initiateTransfer(
            address(token),
            1000 * 1e18,
            137,
            validator1
        );

        vm.stopPrank();

        // Only 2 validators sign (threshold = 3)
        vm.startPrank(validator1);
        bridge.signTransfer(transferId);
        vm.stopPrank();

        vm.startPrank(validator2);
        bridge.signTransfer(transferId);
        vm.stopPrank();

        // Transfer should NOT be executed yet
        assertEq(token.balanceOf(validator1), 0);
        assertEq(bridge.getSignatureCount(transferId), 2);
    }

    function testValidatorCannotSignTwice() public {
        _timelockCall(abi.encodeWithSignature("setPeerBridge(uint256,address)", uint256(137), address(0x123)));

        vm.startPrank(user);

        token.approve(address(bridge), 1000 * 1e18);

        bytes32 transferId = bridge.initiateTransfer(
            address(token),
            1000 * 1e18,
            137,
            validator1
        );

        vm.stopPrank();

        // Validator 1 signs
        vm.startPrank(validator1);
        bridge.signTransfer(transferId);
        vm.stopPrank();

        // Try to sign again - should fail
        vm.startPrank(validator1);
        vm.expectRevert("Already signed");
        bridge.signTransfer(transferId);
        vm.stopPrank();
    }

    /* --------------------------- Gas Comparison Tests --------------------------- */

    function testGasSavingsPermitVsApprove() public {
        vm.startPrank(user);

        uint256 amount = 1000 * 1e6;

        // Measure gas for regular approve
        uint256 gasBefore = gasleft();
        token.approve(address(bridge), amount);
        uint256 gasAfter = gasleft();
        uint256 gasApprove = gasBefore - gasAfter;

        // Reset nonce
        token.nonces(user);

        // Measure gas for permit (off-chain signature, on-chain execution)
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(bridge),
                            amount,
                            token.nonces(user),
                            deadline
                        )
                    )
                )
            )
        );

        gasBefore = gasleft();
        token.permit(user, address(bridge), amount, deadline, v, r, s);
        gasAfter = gasleft();
        uint256 gasPermit = gasBefore - gasAfter;

        // No "savings = approve - permit" here: permit is not cheaper than an approve in
        // a single-call measurement (it verifies an ECDSA signature and an EIP-712 digest).
        // The saving is the approve transaction the user no longer has to send, which this
        // harness cannot measure; asserting a positive difference only produced an
        // underflow panic.
        console.log("Gas for approve:", gasApprove);
        console.log("Gas for permit:", gasPermit);
        assertEq(token.allowance(user, address(bridge)), amount);
        assertGt(gasPermit, 0);

        vm.stopPrank();
    }
}
