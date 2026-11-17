// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LXON} from "../contracts/LXON.sol";

contract LXONTest is Test {
    LXON public lxon;
    address public admin;
    address public minter;
    address public oracle;
    address public guardian;
    address public user1;
    address public user2;

    bytes32 constant MINT_ROLE = bytes32(uint256(keccak256("MINT_ROLE")));
    bytes32 constant ORACLE_ROLE = bytes32(uint256(keccak256("ORACLE_ROLE")));
    bytes32 constant GUARDIAN_ROLE = bytes32(uint256(keccak256("GUARDIAN_ROLE")));
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

    function setUp() public {
        admin = address(this);
        minter = makeAddr("minter");
        oracle = makeAddr("oracle");
        guardian = makeAddr("guardian");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        lxon = new LXON(admin);
        lxon.grantRole(MINT_ROLE, minter);
        lxon.grantRole(ORACLE_ROLE, oracle);
        lxon.grantRole(GUARDIAN_ROLE, guardian);
    }

    function test_LXON_Initialization() public view {
        assertEq(lxon.name(), "LXON Settlement Asset");
        assertEq(lxon.symbol(), "LXON");
        assertEq(lxon.decimals(), 6);
        assertEq(lxon.totalSupply(), 0);
        assertEq(lxon.reserveCeiling(), 0);
        assertEq(lxon.pendingRedeem(), 0);
    }

    function test_LXON_Mint() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0)); // $1M ceiling

        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0)); // $10,000

        assertEq(lxon.balanceOf(user1), 10000000000); // 10,000 * 1e4
        assertEq(lxon.totalSupply(), 10000000000);
    }

    function test_LXON_Mint_ExceedsCeiling() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0)); // $1M ceiling

        vm.prank(minter);
        vm.expectRevert("LXON: exceeds attested reserves");
        lxon.mint(user1, 100000001, bytes32(0)); // Try to mint > ceiling
    }

    function test_LXON_Mint_WithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        lxon.mint(user2, 1000000, bytes32(0));
    }

    function test_LXON_Mint_WhenPaused() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));

        vm.prank(guardian);
        lxon.pause();

        vm.prank(minter);
        vm.expectRevert();
        lxon.mint(user1, 1000000, bytes32(0));
    }

    function test_LXON_Redeem() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));

        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(user1);
        lxon.redeem(5000000000, bytes32(0)); // Redeem $5,000

        assertEq(lxon.balanceOf(user1), 5000000000);
        assertEq(lxon.pendingRedeem(), 500000); // $5,000 in cents
    }

    function test_LXON_Redeem_InsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert("LXON: insufficient balance");
        lxon.redeem(1000000, bytes32(0));
    }

    function test_LXON_Redeem_WhenPaused() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));
        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(guardian);
        lxon.pause();

        vm.prank(user1);
        vm.expectRevert();
        lxon.redeem(1000000, bytes32(0));
    }

    function test_LXON_UpdateCeiling() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));

        assertEq(lxon.reserveCeiling(), 100000000);
    }

    function test_LXON_UpdateCeiling_WithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        lxon.updateCeiling(100000000, bytes32(0));
    }

    function test_LXON_SettleRedeemed() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));
        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(user1);
        lxon.redeem(5000000000, bytes32(0));

        vm.prank(guardian);
        lxon.settleRedeemed(500000);

        assertEq(lxon.pendingRedeem(), 0);
    }

    function test_LXON_SettleRedeemed_OverSettle() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));
        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(user1);
        lxon.redeem(5000000000, bytes32(0));

        vm.prank(guardian);
        vm.expectRevert("LXON: over-settle");
        lxon.settleRedeemed(600000);
    }

    function test_LXON_SettleRedeemed_WithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        lxon.settleRedeemed(100000);
    }

    function test_LXON_Pause() public {
        vm.prank(guardian);
        lxon.pause();

        assertTrue(lxon.paused());
    }

    function test_LXON_Pause_WithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        lxon.pause();
    }

    function test_LXON_Unpause() public {
        vm.prank(guardian);
        lxon.pause();

        vm.prank(minter);
        lxon.unpause();

        assertFalse(lxon.paused());
    }

    function test_LXON_Unpause_WithoutRole() public {
        vm.prank(guardian);
        lxon.pause();

        vm.prank(user1);
        vm.expectRevert();
        lxon.unpause();
    }

    function test_LXON_Transfer() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));
        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(user1);
        lxon.transfer(user2, 5000000000);

        assertEq(lxon.balanceOf(user1), 5000000000);
        assertEq(lxon.balanceOf(user2), 5000000000);
    }

    function test_LXON_ApproveAndTransferFrom() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0));
        vm.prank(minter);
        lxon.mint(user1, 1000000, bytes32(0));

        vm.prank(user1);
        lxon.approve(user2, 5000000000);

        vm.prank(user2);
        lxon.transferFrom(user1, user2, 5000000000);

        assertEq(lxon.balanceOf(user1), 5000000000);
        assertEq(lxon.balanceOf(user2), 5000000000);
    }

    function test_LXON_GrantRole() public {
        address newMinter = makeAddr("newMinter");
        vm.prank(admin);
        lxon.grantRole(MINT_ROLE, newMinter);

        assertTrue(lxon.hasRole(MINT_ROLE, newMinter));
    }

    function test_LXON_RevokeRole() public {
        vm.prank(admin);
        lxon.revokeRole(MINT_ROLE, minter);

        assertFalse(lxon.hasRole(MINT_ROLE, minter));
    }

    function test_LXON_RoleManagement_WithoutAdmin() public {
        address newMinter = makeAddr("newMinter");
        vm.prank(user1);
        vm.expectRevert();
        lxon.grantRole(MINT_ROLE, newMinter);
    }

    function test_LXON_Mint_ConstraintsWithPendingRedeem() public {
        vm.prank(oracle);
        lxon.updateCeiling(100000000, bytes32(0)); // $1M ceiling
        vm.prank(minter);
        lxon.mint(user1, 50000000, bytes32(0)); // $500,000 (mints 500,000 * 1e4 = 5,000,000,000)

        vm.prank(user1);
        lxon.redeem(25000000000, bytes32(0)); // Redeem $250,000 (burns 2,500,000,000, adds 250,000 to pendingRedeem)

        // Now: totalSupply = 2,500,000,000, pendingRedeem = 250,000
        // Ceiling check: totalSupply + newAmount <= (ceiling - pendingRedeem) * 1e4
        // Ceiling check: 2,500,000,000 + newAmount <= (100,000,000 - 250,000) * 1e4
        // Ceiling check: 2,500,000,000 + newAmount <= 99,750,000 * 1e4 = 997,500,000,000
        // So we can mint up to 995,000,000,000 more (about $99.5M)

        vm.prank(minter);
        lxon.mint(user2, 50000000, bytes32(0)); // $500,000 more - should succeed

        // Try to mint $1M more - should fail
        vm.prank(minter);
        vm.expectRevert("LXON: exceeds attested reserves");
        lxon.mint(user2, 100000000, bytes32(0));
    }
}
