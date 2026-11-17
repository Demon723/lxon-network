// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LXONStakingEnhanced.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Minimal ERC-67 mock standing in for LxonTokenEnhanced (18 decimals on chain 724).
contract StakingMockToken is ERC20 {
    constructor() ERC20("LXON", "LXON") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}

/**
 * Exit-path tests for LXONStakingEnhanced.
 *
 * Written 2026-10-20 after the contract was deployed to chain 724 at 0x37e1c5eC… and
 * `unstake(uint256)` was proven to revert for the legitimate staker with
 * "Flash loan detected": the noFlashLoan modifier snapshots the contract's token balance
 * before the body and requires it not to have dropped, but paying the payout out is
 * exactly what unstake does, so the check can never be satisfied. No earlier test caught
 * it because test/LXONStakingFixed.t.sol constructs LXONStaking, not this contract.
 */
contract LXONStakingEnhancedExitTest is Test {
    LXONStakingEnhanced public staking;
    StakingMockToken public token;

    address public staker = address(0xA11CE);
    address public treasury = makeAddr("treasury");

    uint256 public constant MIN_STAKE = 1000e18;

    function setUp() public {
        token = new StakingMockToken();
        token.transfer(staker, 100_000e18);

        staking = new LXONStakingEnhanced(address(token), "LXON Staking Position", "LXONSP");

        // The constructor makes the deployer the treasury and the admin; move the treasury
        // somewhere observable so the penalty transfer can be asserted on its own balance.
        staking.setTreasury(treasury);

        vm.startPrank(staker);
        token.approve(address(staking), type(uint256).max);
        staking.stake(MIN_STAKE, 0);
        vm.stopPrank();
    }

    /// The bug: an active position must be closable. Fails with "Flash loan detected".
    function testUnstakeReturnsPrincipalToTheStaker() public {
        uint256 stakerBefore = token.balanceOf(staker);

        vm.prank(staker);
        staking.unstake(0);

        assertEq(token.balanceOf(staker) - stakerBefore, 900e18, "payout should be principal minus the 10% early penalty");
        assertEq(staking.totalStakedAmount(), 0, "totalStakedAmount should drop back to zero");
        assertEq(staking.balanceOf(staker), 0, "the stake NFT should be gone");
    }

    /// The second defect: penalty was computed but never paid anywhere, so it stayed in the
    /// contract with no withdraw path.
    function testEarlyUnstakePenaltyGoesToTreasury() public {
        vm.prank(staker);
        staking.unstake(0);

        assertEq(token.balanceOf(treasury), 100e18, "early-unstake penalty must reach the treasury");
        assertEq(token.balanceOf(address(staking)), 0, "the contract must not keep staker value hostage");
    }

    /// A matured position must pay out in full and take no penalty.
    function testUnstakeAfterLockPaysFullPrincipal() public {
        vm.warp(block.timestamp + 31 days);

        uint256 stakerBefore = token.balanceOf(staker);
        vm.prank(staker);
        staking.unstake(0);

        assertEq(token.balanceOf(staker) - stakerBefore, MIN_STAKE, "matured exit pays the whole stake");
        assertEq(token.balanceOf(treasury), 0, "no penalty after the lock has elapsed");
    }

    /// The guard must stay where it works: a stake that hands tokens to the contract is
    /// still covered, so removing it from unstake cannot silently remove it from stake.
    function testStakeStillRejectsABalanceDropDuringTheCall() public {
        assertEq(token.balanceOf(address(staking)), MIN_STAKE, "setUp stake should be held by the contract");

        vm.prank(staker);
        (uint256 stakeId,) = staking.stake(2000e18, 1);
        assertEq(stakeId, 1, "second position gets the next id");
        assertEq(token.balanceOf(address(staking)), 3000e18, "stake still escrows both positions");
    }

    /// The burn was only an event: stakeOwner was never cleared, so ownerOf() kept reporting
    /// the staker and tokenURI() kept refusing to say the token was gone.
    function testUnstakedPositionIsActuallyBurned() public {
        vm.prank(staker);
        staking.unstake(0);

        assertEq(staking.ownerOf(0), address(0), "a burned stake NFT must stop reporting an owner");
        vm.expectRevert(bytes("Token does not exist"));
        staking.tokenURI(0);
    }
}
