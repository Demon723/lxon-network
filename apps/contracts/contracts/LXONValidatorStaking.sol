// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title LXONValidatorStaking
 * @dev Validator staking contract for LXON PoS transition
 *      - 3 validator tiers (10K, 50K, 500K LXON minimum stakes)
 *      - Slashing conditions for misbehavior
 *      - Reward distribution based on tier and performance
 *      - 21-day unbonding period
 *      - Timelock-protected governance
 */
contract LXONValidatorStaking is AccessControl {
    // ============ Constants ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");

    // Tier stake requirements (in LXON, 4 decimals as per LXON token)
    uint256 public constant TIER_1_MIN_STAKE = 10_000 * 1e4;    // 10K LXON
    uint256 public constant TIER_2_MIN_STAKE = 50_000 * 1e4;    // 50K LXON
    uint256 public constant TIER_3_MIN_STAKE = 500_000 * 1e4;   // 500K LXON

    // Unbonding period (21 days)
    uint256 public constant UNBONDING_PERIOD = 21 * 24 * 60 * 60;

    // Slashing penalties (basis points)
    uint256 public constant CRITICAL_SLASH = 10000;  // 100%
    uint256 public constant MODERATE_SLASH = 5000;    // 50%
    uint256 public constant MINOR_SLASH = 1000;       // 10%

    // Performance metrics
    uint256 public constant REQUIRED_UPTIME_TIER_1 = 95 * 100;   // 95%
    uint256 public constant REQUIRED_UPTIME_TIER_2 = 99 * 100;  // 99%
    uint256 public constant REQUIRED_UPTIME_TIER_3 = 99.9 * 100; // 99.9%

    // Reward rates (annual APY in basis points)
    uint256 public constant TIER_1_APY = 500;    // 5%
    uint256 public constant TIER_2_APY = 1000;   // 10%
    uint256 public constant TIER_3_APY = 1500;   // 15%

    // ============ Structs ============
    struct ValidatorInfo {
        address operator;
        uint256 stakeAmount;
        uint256 tier;
        uint256 registeredAt;
        uint256 lastRewardClaim;
        uint256 uptimeScore;    // in basis points (0-10000)
        uint256 slashCount;
        bool active;
        bool inUnbonding;
        uint256 unbondingStartedAt;
    }

    struct UnbondingRequest {
        uint256 amount;
        uint256 requestTime;
        bool processed;
    }

    struct SlashingRecord {
        uint256 timestamp;
        uint256 amount;
        uint256 tier;
        string reason;
    }

    // ============ State ============
    IERC20 public immutable lxonToken;
    TimelockController public timelock;

    // Validator registry
    mapping(address => ValidatorInfo) public validators;
    address[] public validatorList;
    mapping(uint256 => address[]) public validatorsByTier;

    // Unbonding requests
    mapping(address => UnbondingRequest[]) public unbondingRequests;

    // Slashing records
    mapping(address => uint256) public totalSlashed;
    mapping(address => SlashingRecord[]) public slashingHistory;

    // Global state
    uint256 public totalStaked;
    uint256 public totalValidators;
    uint256 public activeValidators;
    uint256 public rewardPool;

    // ============ Events ============
    event ValidatorRegistered(address indexed operator, uint256 tier, uint256 amount);
    event ValidatorUnbondingStarted(address indexed operator, uint256 amount);
    event ValidatorUnbonded(address indexed operator, uint256 amount);
    event ValidatorSlashed(address indexed operator, uint256 amount, uint256 tier, string reason);
    event RewardClaimed(address indexed operator, uint256 amount);
    event RewardPoolFunded(uint256 amount);
    event UptimeScoreUpdated(address indexed operator, uint256 oldScore, uint256 newScore);
    event TierChanged(address indexed operator, uint256 oldTier, uint256 newTier);

    // ============ Modifiers ============
    modifier onlyActiveValidator(address _operator) {
        require(validators[_operator].active, "LXONValidatorStaking: validator not active");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == address(timelock), "LXONValidatorStaking: only timelock");
        _;
    }

    // ============ Constructor ============
    /**
     * @param _lxonToken Address of LXON token
     * @param _timelockDelay Delay for timelock operations (in seconds)
     */
    constructor(address _lxonToken, uint256 _timelockDelay) {
        require(_lxonToken != address(0), "LXONValidatorStaking: invalid token");
        require(_timelockDelay >= 1 days, "LXONValidatorStaking: timelock too short");

        lxonToken = IERC20(_lxonToken);

        // Setup timelock
        address[] memory proposers = new address[](1);
        proposers[0] = msg.sender;

        address[] memory executors = new address[](1);
        executors[0] = msg.sender;

        timelock = new TimelockController(
            _timelockDelay,
            proposers,
            executors,
            address(0)
        );

        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SLASHER_ROLE, msg.sender);
        _grantRole(REWARD_DISTRIBUTOR_ROLE, msg.sender);
    }

    // ============ Validator Registration ============

    /**
     * @dev Register as a validator with stake
     * @param _amount Amount of LXON to stake
     */
    function registerValidator(uint256 _amount) external {
        require(_amount >= TIER_1_MIN_STAKE, "LXONValidatorStaking: below minimum stake");
        require(!validators[msg.sender].active, "LXONValidatorStaking: already registered");

        // Transfer tokens from validator to contract
        require(
            lxonToken.transferFrom(msg.sender, address(this), _amount),
            "LXONValidatorStaking: transfer failed"
        );

        // Determine tier based on stake amount
        uint256 tier;
        if (_amount >= TIER_3_MIN_STAKE) {
            tier = 3;
        } else if (_amount >= TIER_2_MIN_STAKE) {
            tier = 2;
        } else {
            tier = 1;
        }

        // Register validator
        validators[msg.sender] = ValidatorInfo({
            operator: msg.sender,
            stakeAmount: _amount,
            tier: tier,
            registeredAt: block.timestamp,
            lastRewardClaim: block.timestamp,
            uptimeScore: 10000,  // Start with 100% uptime
            slashCount: 0,
            active: true,
            inUnbonding: false,
            unbondingStartedAt: 0
        });

        validatorList.push(msg.sender);
        validatorsByTier[tier].push(msg.sender);

        totalStaked += _amount;
        totalValidators++;
        activeValidators++;

        emit ValidatorRegistered(msg.sender, tier, _amount);
    }

    /**
     * @dev Increase validator stake (may trigger tier upgrade)
     * @param _amount Additional amount to stake
     */
    function increaseStake(uint256 _amount) external onlyActiveValidator(msg.sender) {
        require(_amount > 0, "LXONValidatorStaking: zero amount");

        // Transfer additional tokens
        require(
            lxonToken.transferFrom(msg.sender, address(this), _amount),
            "LXONValidatorStaking: transfer failed"
        );

        ValidatorInfo storage validator = validators[msg.sender];
        uint256 oldTier = validator.tier;
        uint256 newStakeAmount = validator.stakeAmount + _amount;

        // Update stake
        validator.stakeAmount = newStakeAmount;
        totalStaked += _amount;

        // Check for tier upgrade
        uint256 newTier;
        if (newStakeAmount >= TIER_3_MIN_STAKE) {
            newTier = 3;
        } else if (newStakeAmount >= TIER_2_MIN_STAKE) {
            newTier = 2;
        } else {
            newTier = 1;
        }

        if (newTier != oldTier) {
            _updateValidatorTier(msg.sender, oldTier, newTier);
        }
    }

    /**
     * @dev Decrease validator stake (may trigger tier downgrade)
     * @param _amount Amount to unstake
     */
    function decreaseStake(uint256 _amount) external onlyActiveValidator(msg.sender) {
        require(_amount > 0, "LXONValidatorStaking: zero amount");
        require(_amount < validators[msg.sender].stakeAmount, "LXONValidatorStaking: cannot unstake all");

        ValidatorInfo storage validator = validators[msg.sender];
        uint256 oldTier = validator.tier;
        uint256 newStakeAmount = validator.stakeAmount - _amount;

        // Ensure minimum stake after decrease
        require(newStakeAmount >= TIER_1_MIN_STAKE, "LXONValidatorStaking: below minimum after decrease");

        // Transfer tokens back
        lxonToken.transfer(msg.sender, _amount);

        // Update stake
        validator.stakeAmount = newStakeAmount;
        totalStaked -= _amount;

        // Check for tier downgrade
        uint256 newTier;
        if (newStakeAmount >= TIER_3_MIN_STAKE) {
            newTier = 3;
        } else if (newStakeAmount >= TIER_2_MIN_STAKE) {
            newTier = 2;
        } else {
            newTier = 1;
        }

        if (newTier != oldTier) {
            _updateValidatorTier(msg.sender, oldTier, newTier);
        }
    }

    // ============ Unbonding ============

    /**
     * @dev Start unbonding process (21-day wait period)
     */
    function startUnbonding() external onlyActiveValidator(msg.sender) {
        require(!validators[msg.sender].inUnbonding, "LXONValidatorStaking: already unbonding");

        ValidatorInfo storage validator = validators[msg.sender];
        validator.inUnbonding = true;
        validator.unbondingStartedAt = block.timestamp;

        unbondingRequests[msg.sender].push(UnbondingRequest({
            amount: validator.stakeAmount,
            requestTime: block.timestamp,
            processed: false
        }));

        activeValidators--;
        emit ValidatorUnbondingStarted(msg.sender, validator.stakeAmount);
    }

    /**
     * @dev Complete unbonding and withdraw stake (after 21 days)
     */
    function completeUnbonding() external {
        ValidatorInfo storage validator = validators[msg.sender];
        require(validator.inUnbonding, "LXONValidatorStaking: not unbonding");
        require(
            block.timestamp >= validator.unbondingStartedAt + UNBONDING_PERIOD,
            "LXONValidatorStaking: unbonding period not elapsed"
        );

        uint256 amount = validator.stakeAmount;

        // Mark as inactive
        validator.active = false;
        validator.inUnbonding = false;
        validator.stakeAmount = 0;

        // Transfer stake back
        lxonToken.transfer(msg.sender, amount);

        totalStaked -= amount;

        emit ValidatorUnbonded(msg.sender, amount);
    }

    /**
     * @dev Cancel unbonding and remain active
     */
    function cancelUnbonding() external onlyActiveValidator(msg.sender) {
        require(validators[msg.sender].inUnbonding, "LXONValidatorStaking: not unbonding");

        ValidatorInfo storage validator = validators[msg.sender];
        validator.inUnbonding = false;
        validator.unbondingStartedAt = 0;

        activeValidators++;
    }

    // ============ Slashing ============

    /**
     * @dev Slash a validator for misbehavior
     * @param _operator Validator to slash
     * @param _penaltyTier Penalty tier (1=minor, 2=moderate, 3=critical)
     * @param _reason Reason for slashing
     */
    function slashValidator(
        address _operator,
        uint256 _penaltyTier,
        string calldata _reason
    ) external onlyRole(SLASHER_ROLE) {
        require(validators[_operator].active, "LXONValidatorStaking: validator not active");
        require(_penaltyTier >= 1 && _penaltyTier <= 3, "LXONValidatorStaking: invalid penalty tier");

        ValidatorInfo storage validator = validators[_operator];
        uint256 slashAmount;
        uint256 penaltyBps;

        if (_penaltyTier == 3) {
            // Critical: 100% slash
            penaltyBps = CRITICAL_SLASH;
            slashAmount = validator.stakeAmount;
            validator.active = false;
            activeValidators--;
        } else if (_penaltyTier == 2) {
            // Moderate: 50% slash
            penaltyBps = MODERATE_SLASH;
            slashAmount = (validator.stakeAmount * penaltyBps) / 10000;
        } else {
            // Minor: 10% slash
            penaltyBps = MINOR_SLASH;
            slashAmount = (validator.stakeAmount * penaltyBps) / 10000;
        }

        // Transfer slashed amount to treasury (timelock/owner)
        lxonToken.transfer(address(timelock), slashAmount);

        // Update validator state
        validator.stakeAmount -= slashAmount;
        validator.slashCount++;
        totalStaked -= slashAmount;
        totalSlashed[_operator] += slashAmount;

        // Record slashing event
        slashingHistory[_operator].push(SlashingRecord({
            timestamp: block.timestamp,
            amount: slashAmount,
            tier: _penaltyTier,
            reason: _reason
        }));

        emit ValidatorSlashed(_operator, slashAmount, _penaltyTier, _reason);
    }

    /**
     * @dev Update validator uptime score
     * @param _operator Validator to update
     * @param _score New uptime score (in basis points, 0-10000)
     */
    function updateUptimeScore(address _operator, uint256 _score) external onlyRole(SLASHER_ROLE) {
        require(_score <= 10000, "LXONValidatorStaking: invalid score");
        require(validators[_operator].active, "LXONValidatorStaking: validator not active");

        ValidatorInfo storage validator = validators[_operator];
        uint256 oldScore = validator.uptimeScore;
        validator.uptimeScore = _score;

        emit UptimeScoreUpdated(_operator, oldScore, _score);
    }

    // ============ Rewards ============

    /**
     * @dev Fund the reward pool
     * @param _amount Amount to add to reward pool
     */
    function fundRewardPool(uint256 _amount) external onlyRole(REWARD_DISTRIBUTOR_ROLE) {
        require(_amount > 0, "LXONValidatorStaking: zero amount");

        require(
            lxonToken.transferFrom(msg.sender, address(this), _amount),
            "LXONValidatorStaking: transfer failed"
        );

        rewardPool += _amount;
        emit RewardPoolFunded(_amount);
    }

    /**
     * @dev Claim staking rewards
     */
    function claimReward() external onlyActiveValidator(msg.sender) {
        ValidatorInfo storage validator = validators[msg.sender];

        uint256 reward = calculateReward(msg.sender);
        require(reward > 0, "LXONValidatorStaking: no reward");
        require(rewardPool >= reward, "LXONValidatorStaking: insufficient reward pool");

        validator.lastRewardClaim = block.timestamp;
        rewardPool -= reward;

        lxonToken.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @dev Calculate pending reward for a validator
     * @param _operator Validator address
     * @return Pending reward amount
     */
    function calculateReward(address _operator) public view returns (uint256) {
        ValidatorInfo memory validator = validators[_operator];
        if (!validator.active) return 0;

        uint256 elapsed = block.timestamp - validator.lastRewardClaim;
        uint256 tierAPY = validator.tier == 3 ? TIER_3_APY :
                          validator.tier == 2 ? TIER_2_APY : TIER_1_APY;

        // Apply uptime bonus/penalty
        uint256 uptimeMultiplier = validator.uptimeScore;  // in basis points

        // Calculate reward: stake * (APY * elapsed / year) * uptime / 10000
        uint256 annualReward = (validator.stakeAmount * tierAPY) / 10000;
        uint256 timeWeightedReward = (annualReward * elapsed) / (365 * 24 * 60 * 60);
        uint256 adjustedReward = (timeWeightedReward * uptimeMultiplier) / 10000;

        return adjustedReward;
    }

    // ============ View Functions ============

    /**
     * @dev Get validator info
     * @param _operator Validator address
     * @return Validator information
     */
    function getValidatorInfo(address _operator) external view returns (ValidatorInfo memory) {
        return validators[_operator];
    }

    /**
     * @dev Get all validators
     * @return List of validator addresses
     */
    function getAllValidators() external view returns (address[] memory) {
        return validatorList;
    }

    /**
     * @dev Get validators by tier
     * @param _tier Tier number (1, 2, or 3)
     * @return List of validator addresses in that tier
     */
    function getValidatorsByTier(uint256 _tier) external view returns (address[] memory) {
        return validatorsByTier[_tier];
    }

    /**
     * @dev Get total number of validators
     * @return Total validator count
     */
    function getTotalValidators() external view returns (uint256) {
        return totalValidators;
    }

    /**
     * @dev Get number of active validators
     * @return Active validator count
     */
    function getActiveValidators() external view returns (uint256) {
        return activeValidators;
    }

    // ============ Internal Functions ============

    function _updateValidatorTier(address _operator, uint256 _oldTier, uint256 _newTier) internal {
        ValidatorInfo storage validator = validators[_operator];
        validator.tier = _newTier;

        // Remove from old tier list
        address[] storage oldTierList = validatorsByTier[_oldTier];
        for (uint256 i = 0; i < oldTierList.length; i++) {
            if (oldTierList[i] == _operator) {
                oldTierList[i] = oldTierList[oldTierList.length - 1];
                oldTierList.pop();
                break;
            }
        }

        // Add to new tier list
        validatorsByTier[_newTier].push(_operator);

        emit TierChanged(_operator, _oldTier, _newTier);
    }
}


