// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * StakingRewards
 * --------------
 * Pays "real yield" (from RevenueSplitter) to LXON stakers.
 * Separate from block-reward inflation — this is fee revenue only.
 *
 * Model: pro-rata share of `accRewardPerShare` × stake.
 */
contract StakingRewards is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;

    mapping(address => uint256) public stakeOf;
    mapping(address => uint256) public rewardDebt;
    uint256 public totalStaked;
    uint256 public accRewardPerShare;   // scaled 1e18
    uint256 public totalRewardsDeposited;

    event Staked(address indexed who, uint256 amount);
    event Unstaked(address indexed who, uint256 amount);
    event RewardDeposited(uint256 amount);
    event Claimed(address indexed who, uint256 amount);

    error ZeroAmount();
    error InsufficientStake();

    constructor(address _lxon) Ownable(msg.sender) {
        lxon = IERC20(_lxon);
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _updateReward(msg.sender);
        lxon.safeTransferFrom(msg.sender, address(this), amount);
        stakeOf[msg.sender] += amount;
        totalStaked += amount;
        rewardDebt[msg.sender] = (stakeOf[msg.sender] * accRewardPerShare) / 1e18;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount > stakeOf[msg.sender]) revert InsufficientStake();
        _updateReward(msg.sender);
        stakeOf[msg.sender] -= amount;
        totalStaked -= amount;
        rewardDebt[msg.sender] = (stakeOf[msg.sender] * accRewardPerShare) / 1e18;
        lxon.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claim() external nonReentrant {
        uint256 claimableAmount = _updateReward(msg.sender);
        if (claimableAmount == 0) return;
        rewardDebt[msg.sender] = (stakeOf[msg.sender] * accRewardPerShare) / 1e18;
        lxon.safeTransfer(msg.sender, claimableAmount);
        emit Claimed(msg.sender, claimableAmount);
    }

    /// @notice Called by RevenueSplitter.
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        lxon.safeTransferFrom(msg.sender, address(this), amount);
        if (totalStaked == 0) {
            // No stakers yet — hold as unallocated for the next cycle.
            unallocated += amount;
            totalRewardsDeposited += amount;
            emit RewardDeposited(amount);
            return;
        }
        uint256 usable = amount + unallocated;
        unallocated = 0;
        accRewardPerShare += (usable * 1e18) / totalStaked;
        totalRewardsDeposited += amount;
        emit RewardDeposited(amount);
    }

    uint256 public unallocated;

    function pending(address who) external view returns (uint256) {
        if (stakeOf[who] == 0) return 0;
        return (stakeOf[who] * accRewardPerShare) / 1e18 - rewardDebt[who];
    }

    /**
     * @dev Returns the pending reward for `who` without transferring it.
     * Does NOT update rewardDebt — callers must set it after paying out.
     */
    function _updateReward(address who) internal returns (uint256 pending_) {
        if (stakeOf[who] == 0) return 0;
        pending_ = (stakeOf[who] * accRewardPerShare) / 1e18 - rewardDebt[who];
        return pending_;
    }
}