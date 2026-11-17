// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract YieldFarm is Ownable, ReentrancyGuard {
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    struct Pool {
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 depositedAmount;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    uint256 public rewardPerBlock;
    uint256 public totalAllocPoint;
    uint256 public startBlock;
    uint256 public endBlock;

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function poolLength() external view returns (uint256) {
        return totalAllocPoint > 0 ? 1 : 0;
    }

    function addPool(uint256 allocPoint) external onlyOwner {
        require(totalAllocPoint == 0, "Pool already exists");

        pools[0] = Pool({
            allocPoint: allocPoint,
            lastRewardBlock: block.number > startBlock ? block.number : startBlock,
            accRewardPerShare: 0,
            depositedAmount: 0
        });

        totalAllocPoint = allocPoint;

        emit PoolAdded(0, allocPoint);
    }

    function updatePool(uint256 pid) public {
        Pool storage pool = pools[pid];
        require(pool.allocPoint > 0, "Pool does not exist");

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = multiplier * rewardPerBlock * pool.allocPoint / totalAllocPoint;

        if (pool.depositedAmount > 0) {
            pool.accRewardPerShare += reward * 1e12 / pool.depositedAmount;
        }

        pool.lastRewardBlock = block.number;
    }

    function getMultiplier(uint256 from, uint256 to) public view returns (uint256) {
        if (to <= endBlock) {
            return to - from;
        } else if (from >= endBlock) {
            return 0;
        } else {
            return endBlock - from;
        }
    }

    function pendingReward(uint256 pid, address user) external view returns (uint256) {
        Pool storage pool = pools[pid];
        UserInfo storage user_info = userInfo[pid][user];

        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.depositedAmount;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = multiplier * rewardPerBlock * pool.allocPoint / totalAllocPoint;
            accRewardPerShare += reward * 1e12 / lpSupply;
        }

        return user_info.amount * accRewardPerShare / 1e12 - user_info.rewardDebt;
    }

    function deposit(uint256 pid, uint256 amount) external nonReentrant {
        Pool storage pool = pools[pid];
        UserInfo storage user_info = userInfo[pid][msg.sender];

        require(pool.allocPoint > 0, "Pool does not exist");
        updatePool(pid);

        if (user_info.amount > 0) {
            uint256 pending = user_info.amount * pool.accRewardPerShare / 1e12 - user_info.rewardDebt;
            safeTransferReward(msg.sender, pending);
        }

        if (amount > 0) {
            stakingToken.transferFrom(msg.sender, address(this), amount);
            user_info.amount += amount;
            pool.depositedAmount += amount;
        }

        user_info.rewardDebt = user_info.amount * pool.accRewardPerShare / 1e12;

        emit Deposit(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        Pool storage pool = pools[pid];
        UserInfo storage user_info = userInfo[pid][msg.sender];

        require(user_info.amount >= amount, "Insufficient balance");
        updatePool(pid);

        uint256 pending = user_info.amount * pool.accRewardPerShare / 1e12 - user_info.rewardDebt;
        safeTransferReward(msg.sender, pending);

        if (amount > 0) {
            user_info.amount -= amount;
            pool.depositedAmount -= amount;
            stakingToken.transfer(msg.sender, amount);
        }

        user_info.rewardDebt = user_info.amount * pool.accRewardPerShare / 1e12;

        emit Withdraw(msg.sender, pid, amount);
    }

    function claim(uint256 pid) external nonReentrant {
        Pool storage pool = pools[pid];
        UserInfo storage user_info = userInfo[pid][msg.sender];

        updatePool(pid);

        uint256 pending = user_info.amount * pool.accRewardPerShare / 1e12 - user_info.rewardDebt;
        require(pending > 0, "No rewards to claim");

        user_info.rewardDebt = user_info.amount * pool.accRewardPerShare / 1e12;
        safeTransferReward(msg.sender, pending);

        emit Claim(msg.sender, pid, pending);
    }

    function safeTransferReward(address to, uint256 amount) internal {
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance >= amount, "Insufficient reward tokens");
        rewardToken.transfer(to, amount);
    }

    function setRewardPerBlock(uint256 newRate) external onlyOwner {
        rewardPerBlock = newRate;
    }

    function addRewards(uint256 amount) external onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    function updatePoolAllocPoint(uint256 pid, uint256 allocPoint) external onlyOwner {
        Pool storage pool = pools[pid];
        totalAllocPoint = totalAllocPoint - pool.allocPoint + allocPoint;
        pool.allocPoint = allocPoint;
        updatePool(pid);

        emit PoolUpdated(pid, allocPoint);
    }
}
