// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LXONStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock LXON", "LXON") {
        _mint(msg.sender, 10_000_000 * 10**18);
    }
}

contract LXONStakingFixedTest is Test {
    LXONStaking public staking;
    MockERC20 public lxonToken;
    
    address public owner;
    address public user1;
    address public user2;
    
    uint256 public constant MIN_STAKE = 1000 * 10**18;
    uint256 public constant MAX_STAKE = 1_000_000 * 10**18;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        lxonToken = new MockERC20();
        
        // Transfer tokens to users
        lxonToken.transfer(user1, 1_000_000 * 10**18);
        lxonToken.transfer(user2, 1_000_000 * 10**18);
        
        // Deploy contract
        staking = new LXONStaking(address(lxonToken));
        
        // Fund reward pool
        lxonToken.approve(address(staking), 100_000 * 10**18);
        staking.fundRewardPool(100_000 * 10**18);
    }

    function testDeployment() public {
        assertEq(address(staking.lxonToken()), address(lxonToken));
        assertEq(staking.rewardPool(), 100_000 * 10**18);
    }

    function testAuthorizeForSlash() public {
        staking.authorizeForSlash(user1);
        
        assertTrue(staking.authorizedForSlash(user1));
    }

    function testAuthorizeForSlashUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.authorizeForSlash(user1);
    }

    function testRevokeSlashAuthorization() public {
        staking.authorizeForSlash(user1);
        assertTrue(staking.authorizedForSlash(user1));
        
        staking.revokeSlashAuthorization(user1);
        assertFalse(staking.authorizedForSlash(user1));
    }

    function testRevokeSlashAuthorizationUnauthorized() public {
        staking.authorizeForSlash(user1);
        
        vm.prank(user1);
        vm.expectRevert();
        staking.revokeSlashAuthorization(user1);
    }

    function testApplySlashWithAuthorizationAndApproval() public {
        uint256 slashBps = 500; // 5%
        
        // Authorize user1 for slash
        staking.authorizeForSlash(user1);
        
        // User1 approves contract
        vm.prank(user1);
        lxonToken.approve(address(staking), type(uint256).max);
        
        // User1 has balance
        uint256 userBalance = lxonToken.balanceOf(user1);
        uint256 ownerBalance = lxonToken.balanceOf(owner);
        uint256 expectedSlash = (userBalance * slashBps) / 10000;
        
        // Apply slash
        staking.applySlash(user1, slashBps, 1);
        
        // Verify slash applied - the slash is transferred from user to owner
        assertEq(lxonToken.balanceOf(owner), ownerBalance + expectedSlash);
        assertEq(lxonToken.balanceOf(user1), userBalance - expectedSlash);
    }

    function testApplySlashUnauthorized() public {
        uint256 slashBps = 500;
        
        // User1 approves contract
        vm.prank(user1);
        lxonToken.approve(address(staking), type(uint256).max);
        
        // Not authorized
        vm.expectRevert("User not authorized for slash");
        staking.applySlash(user1, slashBps, 1);
    }

    function testApplySlashWithoutApproval() public {
        uint256 slashBps = 500;
        
        // Authorize user1
        staking.authorizeForSlash(user1);
        
        // User1 does NOT approve contract
        vm.expectRevert("User has not approved this contract");
        staking.applySlash(user1, slashBps, 1);
    }

    function testApplySlashPenaltyTooHigh() public {
        uint256 slashBps = 1500; // 15% - exceeds 1000 (10%)
        
        staking.authorizeForSlash(user1);
        
        vm.prank(user1);
        lxonToken.approve(address(staking), type(uint256).max);
        
        vm.expectRevert("Penalty too high");
        staking.applySlash(user1, slashBps, 1);
    }

    function testApplySlashNoBalance() public {
        uint256 slashBps = 500;
        
        address userWithNoBalance = address(0x3);
        
        staking.authorizeForSlash(userWithNoBalance);
        
        vm.prank(userWithNoBalance);
        lxonToken.approve(address(staking), type(uint256).max);
        
        vm.expectRevert("No balance");
        staking.applySlash(userWithNoBalance, slashBps, 1);
    }

    function testApplySlashUnauthorizedCaller() public {
        uint256 slashBps = 500;
        
        staking.authorizeForSlash(user1);
        
        vm.prank(user1);
        lxonToken.approve(address(staking), type(uint256).max);
        
        vm.prank(user2);
        vm.expectRevert();
        staking.applySlash(user1, slashBps, 1);
    }

    function testStake() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        
        assertEq(staking.totalStaked(user1), stakeAmount);
        assertEq(staking.totalStakedAmount(), stakeAmount);
    }

    function testStakeBelowMinimum() public {
        uint256 stakeAmount = 100 * 10**18; // Below MIN_STAKE
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        vm.expectRevert("Below minimum stake");
        staking.stake(stakeAmount, 0);
    }

    function testStakeAboveMaximum() public {
        uint256 stakeAmount = 2_000_000 * 10**18; // Above MAX_STAKE
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        vm.expectRevert("Above maximum");
        staking.stake(stakeAmount, 0);
    }

    function testUnstake() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Warp past lock period
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(user1);
        staking.unstake(stakeId);
        
        assertEq(staking.totalStaked(user1), 0);
        assertEq(staking.totalStakedAmount(), 0);
    }

    function testUnstakeEarlyPenalty() public {
        uint256 stakeAmount = 10_000 * 10**18;
        uint256 initialBalance = lxonToken.balanceOf(user1);
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Unstake early (before lock period)
        vm.prank(user1);
        staking.unstake(stakeId);
        
        // Should have 10% penalty
        uint256 expectedPayout = stakeAmount - (stakeAmount / 10);
        assertEq(lxonToken.balanceOf(user1), initialBalance - stakeAmount + expectedPayout);
    }

    function testClaimReward() public {
        uint256 stakeAmount = 10_000 * 10**18;
        uint256 initialBalance = lxonToken.balanceOf(user1);
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Warp forward to accrue rewards
        vm.warp(block.timestamp + 30 days);
        
        uint256 reward = staking.calculateReward(stakeId);
        assertGt(reward, 0);
        
        vm.prank(user1);
        staking.claimReward(stakeId);
        
        assertEq(lxonToken.balanceOf(user1), initialBalance - stakeAmount + reward);
    }

    function testClaimRewardInsufficientPool() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Warp far forward to accrue huge reward (10 years)
        vm.warp(block.timestamp + 3650 days);
        
        // First, claim some reward to deplete the pool
        vm.prank(user1);
        staking.claimReward(stakeId);
        
        // Try to claim again - pool should be empty
        vm.prank(user1);
        vm.expectRevert("Insufficient reward pool");
        staking.claimReward(stakeId);
    }

    function testCalculateReward() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Warp 30 days
        vm.warp(block.timestamp + 30 days);
        
        uint256 reward = staking.calculateReward(stakeId);
        assertGt(reward, 0);
    }

    function testCalculateRewardInactiveStake() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), stakeAmount);
        
        vm.prank(user1);
        staking.stake(stakeAmount, 0);
        uint256 stakeId = staking.nextStakeId() - 1;
        
        // Unstake
        vm.warp(block.timestamp + 31 days);
        vm.prank(user1);
        staking.unstake(stakeId);
        
        // Calculate reward for inactive stake
        uint256 reward = staking.calculateReward(stakeId);
        assertEq(reward, 0);
    }

    function testFundRewardPool() public {
        uint256 fundAmount = 50_000 * 10**18;
        
        lxonToken.approve(address(staking), fundAmount);
        staking.fundRewardPool(fundAmount);
        
        assertEq(staking.rewardPool(), 150_000 * 10**18);
    }

    function testFundRewardPoolUnauthorized() public {
        uint256 fundAmount = 50_000 * 10**18;
        
        vm.prank(user1);
        lxonToken.approve(address(staking), fundAmount);
        
        vm.prank(user1);
        vm.expectRevert();
        staking.fundRewardPool(fundAmount);
    }

    function testFundRewardPoolZeroAmount() public {
        vm.expectRevert("Zero amount");
        staking.fundRewardPool(0);
    }
}
