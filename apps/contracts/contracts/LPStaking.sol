// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LPStaking is Ownable, ReentrancyGuard {
    IERC20 public lpToken;
    IERC20 public rewardToken;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public rewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public rewardRate = 1e18; // 1 reward token per second per LP token (scaled)

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _lpToken, address _rewardToken) Ownable(msg.sender) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        lastUpdateTime = block.timestamp;
    }

    function updateReward() public {
        if (block.timestamp > lastUpdateTime && totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - lastUpdateTime;
            uint256 reward = timeElapsed * rewardRate * 1e18 / totalStaked;
            rewardPerToken += reward;
            lastUpdateTime = block.timestamp;
        }
    }

    function earned(address account) public view returns (uint256) {
        Stake memory stake = stakes[account];
        uint256 pendingReward = 0;

        if (totalStaked > 0 && block.timestamp > lastUpdateTime) {
            uint256 timeElapsed = block.timestamp - lastUpdateTime;
            uint256 pendingRewardPerToken = timeElapsed * rewardRate * 1e18 / totalStaked;
            pendingReward = (stake.amount * (rewardPerToken + pendingRewardPerToken)) / 1e18 - stake.rewardDebt;
        } else {
            pendingReward = (stake.amount * rewardPerToken) / 1e18 - stake.rewardDebt;
        }

        return pendingReward;
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        updateReward();

        Stake storage userStake = stakes[msg.sender];
        uint256 rewards = earned(msg.sender);

        if (userStake.amount > 0) {
            safeTransferReward(msg.sender, rewards);
        }

        lpToken.transferFrom(msg.sender, address(this), amount);

        userStake.amount += amount;
        userStake.timestamp = block.timestamp;
        userStake.rewardDebt = (userStake.amount * rewardPerToken) / 1e18;

        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "Insufficient staked amount");

        updateReward();

        uint256 rewards = earned(msg.sender);
        safeTransferReward(msg.sender, rewards);

        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * rewardPerToken) / 1e18;

        totalStaked -= amount;

        lpToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        updateReward();

        uint256 rewards = earned(msg.sender);
        require(rewards > 0, "No rewards to claim");

        Stake storage userStake = stakes[msg.sender];
        userStake.rewardDebt = (userStake.amount * rewardPerToken) / 1e18;

        safeTransferReward(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    function safeTransferReward(address to, uint256 amount) internal {
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance >= amount, "Insufficient reward tokens");
        rewardToken.transfer(to, amount);
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        updateReward();
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    function addRewards(uint256 amount) external onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    function getStakeInfo(address account) external view returns (uint256 amount, uint256 timestamp, uint256 rewards) {
        Stake memory stake = stakes[account];
        return (stake.amount, stake.timestamp, earned(account));
    }
}
