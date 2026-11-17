// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title LXONStakingHardened
 * @dev Hardened staking contract with:
 *      - Subnet-based allocation (Yuma-style)
 *      - Emission weight calculation per subnet
 *      - Taoflow clipping (reduce weight if netStakeFlow < 0)
 *      - Subnet decommissioning
 *      - Role-based access control
 */
contract LXONStakingHardened is AccessControl {
    // ============ Constants ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUBNET_MANAGER_ROLE = keccak256("SUBNET_MANAGER_ROLE");

    uint256 public constant EPOCH_DURATION = 12 hours; // Taoflow clipping epoch
    uint256 public constant MIN_STAKE = 1 ether; // Minimum stake amount

    // ============ Structs ============
    struct StakePosition {
        uint256 amount;
        uint256 lockedUntil;
        bytes32 subnetId;
        uint256 stakedAt;
    }

    struct SubnetInfo {
        uint256 totalStaked;
        int256 netStakeFlow; // +/- for epoch
        uint256 weight; // Emission weight (0-10000 = 0-100%)
        uint256 lastClipped; // Last time Taoflow clipping applied
        bool active;
    }

    // ============ State ============
    IERC20 public lxonToken;
    TimelockController public timelock;
    address public governance;

    // Staking data
    mapping(address => StakePosition[]) public stakePositions;
    mapping(address => uint256) public userStakeCount;
    
    // Subnet data
    mapping(bytes32 => SubnetInfo) public subnets;
    bytes32[] public activeSubnets;
    
    // Global state
    uint256 public totalStaked;
    uint256 public lastEpoch;

    // ============ Events ============
    event Staked(address indexed user, uint256 amount, bytes32 subnetId, uint256 lockDuration);
    event Unstaked(address indexed user, uint256 stakeIndex, uint256 amount);
    event SubnetCreated(bytes32 indexed subnetId, uint256 initialWeight);
    event SubnetDecommissioned(bytes32 indexed subnetId);
    event SubnetWeightUpdated(bytes32 indexed subnetId, uint256 oldWeight, uint256 newWeight);
    event TaofloClipped(bytes32 indexed subnetId, uint256 reduction);
    event RewardsDistributed(bytes32 indexed subnetId, uint256 amount);

    // ============ Modifiers ============
    modifier onlyGovernance() {
        require(
            msg.sender == address(timelock) || msg.sender == governance,
            "LXONStakingHardened: only governance"
        );
        _;
    }

    modifier validSubnet(bytes32 subnetId) {
        require(subnets[subnetId].active, "LXONStakingHardened: subnet not active");
        _;
    }

    // ============ Constructor ============
    /**
     * @param _lxonToken Address of LXON token
     * @param _governance Address of governance contract
     * @param _timelockDelay Delay for timelock operations
     */
    constructor(
        address _lxonToken,
        address _governance,
        uint256 _timelockDelay
    ) {
        require(_lxonToken != address(0), "LXONStakingHardened: invalid token");
        require(_governance != address(0), "LXONStakingHardened: invalid governance");

        lxonToken = IERC20(_lxonToken);
        governance = _governance;

        // Setup timelock
        address[] memory proposers = new address[](1);
        proposers[0] = _governance;

        address[] memory executors = new address[](1);
        executors[0] = _governance;

        timelock = new TimelockController(
            _timelockDelay,
            proposers,
            executors,
            _governance
        );

        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(ADMIN_ROLE, _governance);
        _grantRole(SUBNET_MANAGER_ROLE, address(timelock));

        lastEpoch = block.timestamp;
    }

    // ============ Subnet Management ============

    /**
     * @dev Create a new subnet for staking allocation
     * @param subnetId Unique identifier for subnet
     * @param initialWeight Initial emission weight (0-10000 = 0-100%)
     */
    function createSubnet(bytes32 subnetId, uint256 initialWeight) external onlyRole(SUBNET_MANAGER_ROLE) {
        require(subnetId != bytes32(0), "LXONStakingHardened: invalid subnet ID");
        require(!subnets[subnetId].active, "LXONStakingHardened: subnet already exists");
        require(initialWeight <= 10000, "LXONStakingHardened: weight exceeds 100%");

        subnets[subnetId] = SubnetInfo({
            totalStaked: 0,
            netStakeFlow: 0,
            weight: initialWeight,
            lastClipped: block.timestamp,
            active: true
        });

        activeSubnets.push(subnetId);
        emit SubnetCreated(subnetId, initialWeight);
    }

    /**
     * @dev Decommission a subnet (stop accepting new stakes, close it)
     * @param subnetId Subnet to decommission
     */
    function decommissionSubnet(bytes32 subnetId) external onlyRole(SUBNET_MANAGER_ROLE) {
        require(subnets[subnetId].active, "LXONStakingHardened: subnet not active");
        require(subnets[subnetId].totalStaked == 0, "LXONStakingHardened: subnet still has staked tokens");

        subnets[subnetId].active = false;
        subnets[subnetId].weight = 0;

        // Remove from active subnets list
        for (uint256 i = 0; i < activeSubnets.length; i++) {
            if (activeSubnets[i] == subnetId) {
                activeSubnets[i] = activeSubnets[activeSubnets.length - 1];
                activeSubnets.pop();
                break;
            }
        }

        emit SubnetDecommissioned(subnetId);
    }

    /**
     * @dev Manually update subnet weight (governance)
     * @param subnetId Target subnet
     * @param newWeight New weight (0-10000)
     */
    function updateSubnetWeight(bytes32 subnetId, uint256 newWeight)
        external
        onlyGovernance
        validSubnet(subnetId)
    {
        require(newWeight <= 10000, "LXONStakingHardened: weight exceeds 100%");

        uint256 oldWeight = subnets[subnetId].weight;
        subnets[subnetId].weight = newWeight;

        emit SubnetWeightUpdated(subnetId, oldWeight, newWeight);
    }

    // ============ Staking Functions ============

    /**
     * @dev Stake tokens to a subnet
     * @param amount Amount to stake
     * @param subnetId Target subnet
     * @param lockDuration Lock duration in seconds
     */
    function stake(
        uint256 amount,
        bytes32 subnetId,
        uint256 lockDuration
    ) external validSubnet(subnetId) {
        require(amount >= MIN_STAKE, "LXONStakingHardened: amount below minimum");
        require(lockDuration > 0, "LXONStakingHardened: lock duration must be > 0");

        // Transfer tokens from user to contract
        require(
            lxonToken.transferFrom(msg.sender, address(this), amount),
            "LXONStakingHardened: transfer failed"
        );

        // Create stake position
        uint256 lockedUntil = block.timestamp + lockDuration;
        stakePositions[msg.sender].push(
            StakePosition({
                amount: amount,
                lockedUntil: lockedUntil,
                subnetId: subnetId,
                stakedAt: block.timestamp
            })
        );

        userStakeCount[msg.sender]++;

        // Update subnet info
        subnets[subnetId].totalStaked += amount;
        subnets[subnetId].netStakeFlow += int256(amount); // Track inflow
        totalStaked += amount;

        // Recalculate weights
        _recalculateWeights();

        emit Staked(msg.sender, amount, subnetId, lockDuration);
    }

    /**
     * @dev Unstake tokens (only after lock period)
     * @param stakeIndex Index of stake position
     */
    function unstake(uint256 stakeIndex) external {
        require(stakeIndex < stakePositions[msg.sender].length, "LXONStakingHardened: invalid index");

        StakePosition memory position = stakePositions[msg.sender][stakeIndex];
        require(block.timestamp >= position.lockedUntil, "LXONStakingHardened: tokens locked");

        uint256 amount = position.amount;
        bytes32 subnetId = position.subnetId;

        // Remove stake position
        stakePositions[msg.sender][stakeIndex] = stakePositions[msg.sender][
            stakePositions[msg.sender].length - 1
        ];
        stakePositions[msg.sender].pop();
        userStakeCount[msg.sender]--;

        // Update subnet info
        subnets[subnetId].totalStaked -= amount;
        subnets[subnetId].netStakeFlow -= int256(amount); // Track outflow
        totalStaked -= amount;

        // Transfer tokens back to user
        require(lxonToken.transfer(msg.sender, amount), "LXONStakingHardened: transfer failed");

        // Recalculate weights
        _recalculateWeights();

        emit Unstaked(msg.sender, stakeIndex, amount);
    }

    // ============ Taoflow & Weight Calculation ============

    /**
     * @dev Apply Taoflow clipping to reduce weight if netStakeFlow < 0
     * Called automatically after each epoch or manually
     */
    function applyTaoflowClipping(bytes32 subnetId) external validSubnet(subnetId) {
        SubnetInfo storage subnet = subnets[subnetId];
        uint256 timeSinceLastClip = block.timestamp - subnet.lastClipped;

        require(timeSinceLastClip >= EPOCH_DURATION, "LXONStakingHardened: too soon for clipping");

        // If net flow is negative, reduce weight
        if (subnet.netStakeFlow < 0) {
            uint256 flowMagnitude = uint256(-subnet.netStakeFlow);
            uint256 weightReduction = (subnet.weight * flowMagnitude) / (subnet.totalStaked + 1); // +1 to avoid div by 0
            
            uint256 newWeight = subnet.weight > weightReduction ? subnet.weight - weightReduction : 0;
            uint256 reduction = subnet.weight - newWeight;

            subnet.weight = newWeight;
            emit TaofloClipped(subnetId, reduction);
        }

        // Reset net flow for next epoch
        subnet.netStakeFlow = 0;
        subnet.lastClipped = block.timestamp;
    }

    /**
     * @dev Recalculate weights for all subnets
     * Normalizes weights so they sum to 10000 (100%)
     */
    function _recalculateWeights() internal {
        if (activeSubnets.length == 0) return;

        uint256 totalWeight = 0;
        uint256[] memory newWeights = new uint256[](activeSubnets.length);

        // Calculate based on staked amounts
        for (uint256 i = 0; i < activeSubnets.length; i++) {
            bytes32 subnetId = activeSubnets[i];
            SubnetInfo storage subnet = subnets[subnetId];

            // Weight proportional to staked amount
            if (totalStaked > 0) {
                newWeights[i] = (subnet.totalStaked * 10000) / totalStaked;
            } else {
                newWeights[i] = 0;
            }

            totalWeight += newWeights[i];
        }

        // Normalize if total exceeds 10000
        if (totalWeight > 10000) {
            for (uint256 i = 0; i < activeSubnets.length; i++) {
                newWeights[i] = (newWeights[i] * 10000) / totalWeight;
            }
        }

        // Apply new weights
        for (uint256 i = 0; i < activeSubnets.length; i++) {
            bytes32 subnetId = activeSubnets[i];
            uint256 oldWeight = subnets[subnetId].weight;
            subnets[subnetId].weight = newWeights[i];

            if (oldWeight != newWeights[i]) {
                emit SubnetWeightUpdated(subnetId, oldWeight, newWeights[i]);
            }
        }
    }

    // ============ View Functions ============

    /**
     * @dev Get subnet weight for emission allocation
     */
    function getSubnetWeight(bytes32 subnetId) external view validSubnet(subnetId) returns (uint256) {
        return subnets[subnetId].weight;
    }

    /**
     * @dev Get total staked amount for a subnet
     */
    function getSubnetTotalStaked(bytes32 subnetId) external view validSubnet(subnetId) returns (uint256) {
        return subnets[subnetId].totalStaked;
    }

    /**
     * @dev Get user's stake positions
     */
    function getUserStakes(address user)
        external
        view
        returns (StakePosition[] memory)
    {
        return stakePositions[user];
    }

    /**
     * @dev Get active subnets count
     */
    function getActiveSubnetsCount() external view returns (uint256) {
        return activeSubnets.length;
    }

    /**
     * @dev Get all active subnet IDs
     */
    function getActiveSubnets() external view returns (bytes32[] memory) {
        return activeSubnets;
    }

    /**
     * @dev Calculate user's voting power based on stake
     */
    function getVotingPower(address user) external view returns (uint256) {
        uint256 power = 0;
        for (uint256 i = 0; i < stakePositions[user].length; i++) {
            power += stakePositions[user][i].amount;
        }
        return power;
    }
}
