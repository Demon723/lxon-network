// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {StakingRewards} from "../../src/revenue/StakingRewards.sol";
import {MockERC20} from "../MockERC20.sol";

contract StakingRewardsTest is Test {
    MockERC20 lxon;
    StakingRewards sr;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        lxon = new MockERC20();
        sr = new StakingRewards(address(lxon));
        lxon.mint(alice, 1000 ether);
        lxon.mint(bob, 1000 ether);
        lxon.mint(address(this), 1000 ether);
        vm.prank(alice); lxon.approve(address(sr), type(uint256).max);
        vm.prank(bob);   lxon.approve(address(sr), type(uint256).max);
        lxon.approve(address(sr), type(uint256).max);
    }

    function test_stake_and_claim() public {
        vm.prank(alice); sr.stake(100 ether);
        sr.deposit(10 ether); // revenue
        uint256 pending = sr.pending(alice);
        assertEq(pending, 10 ether);

        vm.prank(alice); sr.claim();
        assertEq(lxon.balanceOf(alice), 910 ether);
    }

    function test_pro_rata() public {
        vm.prank(alice); sr.stake(100 ether);
        vm.prank(bob);   sr.stake(300 ether);
        sr.deposit(40 ether);
        // alice should get 25%, bob 75%
        assertEq(sr.pending(alice), 10 ether);
        assertEq(sr.pending(bob), 30 ether);
    }

    function test_unstake() public {
        vm.prank(alice); sr.stake(100 ether);
        vm.prank(alice); sr.unstake(40 ether);
        assertEq(sr.stakeOf(alice), 60 ether);
        assertEq(sr.totalStaked(), 60 ether);
    }
}
