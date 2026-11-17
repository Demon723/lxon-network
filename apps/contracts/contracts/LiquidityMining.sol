// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LiquidityMining
 * @dev Liquidity mining/staking contract for DEX
 * Rewards liquidity providers with LXON tokens
 */
contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        address lpToken;
        address rewardToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint;
    uint256 public rewardPerSecond;
    uint256 public startTime;
    uint256 public endTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ClaimReward(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address lpToken, uint256 allocPoint);

    constructor(uint256 _rewardPerSecond, uint256 _startTime, uint256 _duration) Ownable(msg.sender) {
        rewardPerSecond = _rewardPerSecond;
        startTime = _startTime;
        endTime = _startTime + _duration;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(address _lpToken, uint256 _allocPoint) external onlyOwner {
        require(_lpToken != address(0), "Invalid LP token");
        
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            rewardToken: address(0), // Will be set separately
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
            accRewardPerShare: 0,
            totalStaked: 0
        }));
        
        totalAllocPoint += _allocPoint;
        emit PoolAdded(poolInfo.length - 1, _lpToken, _allocPoint);
    }

    function setPoolRewardToken(uint256 _pid, address _rewardToken) external onlyOwner {
        require(_pid < poolInfo.length, "Invalid pool");
        poolInfo[_pid].rewardToken = _rewardToken;
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        
        // Return early if no stakers (allows first deposit)
        if (pool.totalStaked == 0) {
            return;
        }

        uint256 lastTime = block.timestamp < endTime ? block.timestamp : endTime;
        if (lastTime <= pool.lastRewardTime) {
            return;
        }

        uint256 rewardDuration = lastTime - pool.lastRewardTime;
        uint256 reward = (rewardDuration * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
        
        pool.accRewardPerShare += (reward * 1e18) / pool.totalStaked;
        pool.lastRewardTime = lastTime;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;
            user.pendingRewards += pending;
        }

        IERC20(pool.lpToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        user.amount += _amount;
        pool.totalStaked += _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e18;

        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "Insufficient balance");

        updatePool(_pid);

        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;
        user.pendingRewards += pending;

        user.amount -= _amount;
        pool.totalStaked -= _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e18;

        IERC20(pool.lpToken).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;
        require(pending > 0 || user.pendingRewards > 0, "No rewards");

        uint256 totalReward = pending + user.pendingRewards;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e18;
        user.pendingRewards = 0;

        if (pool.rewardToken != address(0)) {
            IERC20(pool.rewardToken).safeTransfer(msg.sender, totalReward);
        }

        emit ClaimReward(msg.sender, _pid, totalReward);
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 lastTime = block.timestamp < endTime ? block.timestamp : endTime;
            uint256 rewardDuration = lastTime - pool.lastRewardTime;
            uint256 reward = (rewardDuration * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare += (reward * 1e18) / pool.totalStaked;
        }

        return (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt + user.pendingRewards;
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        rewardPerSecond = _rewardPerSecond;
    }

    function setAllocPoint(uint256 _pid, uint256 _allocPoint) external onlyOwner {
        require(_pid < poolInfo.length, "Invalid pool");
        
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function emergencyWithdraw(uint256 _pid) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 amount = IERC20(pool.lpToken).balanceOf(address(this));
        IERC20(pool.lpToken).safeTransfer(owner(), amount);
    }
}
