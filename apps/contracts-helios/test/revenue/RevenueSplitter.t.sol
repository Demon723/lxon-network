// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {RevenueSplitter} from "../../src/revenue/RevenueSplitter.sol";
import {MockERC20} from "../MockERC20.sol";

contract RevenueSplitterTest is Test {
    MockERC20 lxon;
    RevenueSplitter splitter;

    address owner = address(this);
    address buyback = address(0xB0);
    address stakers = address(0x57);
    address eco = address(0xEC);
    address ops = address(0x0F);

    function setUp() public {
        lxon = new MockERC20();
        splitter = new RevenueSplitter(address(lxon), buyback, stakers, eco, ops);
        lxon.mint(owner, 10_000 ether);
        lxon.approve(address(splitter), type(uint256).max);
    }

    function test_default_split() public {
        (uint16 b, uint16 s, uint16 e, uint16 o) = splitter.split();
        assertEq(b, 4000);
        assertEq(s, 3000);
        assertEq(e, 2000);
        assertEq(o, 1000);
    }

    function test_deposit_splits_correctly() public {
        splitter.deposit(1000 ether, "test");

        assertEq(lxon.balanceOf(buyback), 400 ether);
        assertEq(lxon.balanceOf(stakers), 300 ether);
        assertEq(lxon.balanceOf(eco), 200 ether);
        assertEq(lxon.balanceOf(ops), 100 ether);
        assertEq(splitter.totalReceived(), 1000 ether);
    }

    function test_no_dust_on_odd_amounts() public {
        // 999 wei split must sum exactly
        splitter.deposit(999, "odd");
        uint256 sum = lxon.balanceOf(buyback) + lxon.balanceOf(stakers)
                    + lxon.balanceOf(eco) + lxon.balanceOf(ops);
        assertEq(sum, 999);
    }

    function test_owner_can_retune_split() public {
        splitter.setSplit(6000, 2000, 1000, 1000);
        (uint16 b,,,uint16 o) = splitter.split();
        assertEq(b, 6000);
        assertEq(o, 1000);
    }

    function test_rejects_bad_split_sum() public {
        vm.expectRevert(RevenueSplitter.BadBps.selector);
        splitter.setSplit(5000, 3000, 2000, 1000); // sums to 11000
    }

    function test_non_owner_cannot_retune() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        splitter.setSplit(1000, 1000, 1000, 7000);
    }

    function test_zero_amount_reverts() public {
        vm.expectRevert(RevenueSplitter.ZeroAmount.selector);
        splitter.deposit(0, "zero");
    }
}
