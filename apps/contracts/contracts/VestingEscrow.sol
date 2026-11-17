// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VestingEscrow
 * @dev Vesting contract for team/treasury allocations with:
 *      - Linear vesting with cliff
 *      - Multiple beneficiaries
 *      - Releasable balance calculation
 *      - Role-based access control
 */
contract VestingEscrow is Ownable, ReentrancyGuard {
    // ============ Structs ============
    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffTime; // Time when vesting starts (cliff duration)
        uint256 duration; // Total vesting duration
        bool revocable;
        bool revoked;
    }

    // ============ State ============
    IERC20 public token;
    
    mapping(bytes32 => VestingSchedule) public vestingSchedules;
    bytes32[] public scheduleIds;
    mapping(address => bytes32[]) public beneficiarySchedules;

    uint256 public totalVested;

    // ============ Events ============
    event VestingScheduleCreated(
        bytes32 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    );

    event TokensReleased(
        bytes32 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount
    );

    event VestingRevoked(
        bytes32 indexed scheduleId,
        address indexed beneficiary,
        uint256 releasedAmount,
        uint256 unreleaseAmount
    );

    // ============ Modifiers ============
    modifier validSchedule(bytes32 scheduleId) {
        require(vestingSchedules[scheduleId].beneficiary != address(0), "VestingEscrow: invalid schedule");
        _;
    }

    // ============ Constructor ============
    /**
     * @param _token LXON token address
     */
    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "VestingEscrow: invalid token");
        token = IERC20(_token);
    }

    // ============ Vesting Schedule Creation ============

    /**
     * @dev Create a new vesting schedule
     * @param beneficiary Address to receive tokens
     * @param amount Total tokens to vest
     * @param startTime When vesting begins
     * @param cliffDuration Time before vesting starts (cliff)
     * @param duration Total vesting duration (including cliff)
     * @param revocable Whether admin can revoke vesting
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) external onlyOwner returns (bytes32) {
        require(beneficiary != address(0), "VestingEscrow: invalid beneficiary");
        require(amount > 0, "VestingEscrow: amount must be > 0");
        require(duration > 0, "VestingEscrow: duration must be > 0");
        require(cliffDuration <= duration, "VestingEscrow: cliff > duration");
        require(startTime > block.timestamp, "VestingEscrow: start time must be in future");

        // Generate unique schedule ID
        bytes32 scheduleId = keccak256(
            abi.encodePacked(beneficiary, amount, startTime, block.timestamp)
        );

        require(
            vestingSchedules[scheduleId].beneficiary == address(0),
            "VestingEscrow: schedule already exists"
        );

        // Create vesting schedule
        vestingSchedules[scheduleId] = VestingSchedule({
            beneficiary: beneficiary,
            totalAmount: amount,
            releasedAmount: 0,
            startTime: startTime,
            cliffTime: startTime + cliffDuration,
            duration: duration,
            revocable: revocable,
            revoked: false
        });

        scheduleIds.push(scheduleId);
        beneficiarySchedules[beneficiary].push(scheduleId);
        totalVested += amount;

        // Transfer tokens to escrow
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "VestingEscrow: transfer failed"
        );

        emit VestingScheduleCreated(
            scheduleId,
            beneficiary,
            amount,
            startTime,
            cliffDuration,
            duration,
            revocable
        );

        return scheduleId;
    }

    // ============ Release Functions ============

    /**
     * @dev Release vested tokens for a schedule
     * @param scheduleId Schedule ID
     */
    function release(bytes32 scheduleId)
        external
        nonReentrant
        validSchedule(scheduleId)
    {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        require(!schedule.revoked, "VestingEscrow: schedule revoked");
        require(msg.sender == schedule.beneficiary, "VestingEscrow: not beneficiary");

        uint256 releasable = getReleasableAmount(scheduleId);
        require(releasable > 0, "VestingEscrow: no releasable tokens");

        schedule.releasedAmount += releasable;

        require(token.transfer(schedule.beneficiary, releasable), "VestingEscrow: transfer failed");

        emit TokensReleased(scheduleId, schedule.beneficiary, releasable);
    }

    /**
     * @dev Release vested tokens to all schedules of a beneficiary
     */
    function releaseAll() external nonReentrant {
        bytes32[] storage schedules = beneficiarySchedules[msg.sender];
        require(schedules.length > 0, "VestingEscrow: no schedules");

        uint256 totalReleasable = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            bytes32 scheduleId = schedules[i];
            VestingSchedule storage schedule = vestingSchedules[scheduleId];

            if (!schedule.revoked) {
                uint256 releasable = getReleasableAmount(scheduleId);
                if (releasable > 0) {
                    schedule.releasedAmount += releasable;
                    totalReleasable += releasable;
                    emit TokensReleased(scheduleId, msg.sender, releasable);
                }
            }
        }

        require(totalReleasable > 0, "VestingEscrow: no releasable tokens");
        require(token.transfer(msg.sender, totalReleasable), "VestingEscrow: transfer failed");
    }

    // ============ Revocation ============

    /**
     * @dev Revoke a vesting schedule (only if revocable and owner)
     * Unreleased tokens returned to owner
     * @param scheduleId Schedule ID
     */
    function revokeSchedule(bytes32 scheduleId)
        external
        onlyOwner
        validSchedule(scheduleId)
    {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        require(schedule.revocable, "VestingEscrow: not revocable");
        require(!schedule.revoked, "VestingEscrow: already revoked");

        schedule.revoked = true;

        uint256 unreleased = schedule.totalAmount - schedule.releasedAmount;
        if (unreleased > 0) {
            totalVested -= unreleased;
            require(token.transfer(owner(), unreleased), "VestingEscrow: transfer failed");
        }

        emit VestingRevoked(
            scheduleId,
            schedule.beneficiary,
            schedule.releasedAmount,
            unreleased
        );
    }

    // ============ View Functions ============

    /**
     * @dev Calculate vested amount at current time
     */
    function getVestedAmount(bytes32 scheduleId)
        public
        view
        validSchedule(scheduleId)
        returns (uint256)
    {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];

        // Before cliff, nothing is vested
        if (block.timestamp < schedule.cliffTime) {
            return 0;
        }

        // After duration, all is vested
        uint256 vestedTime = schedule.startTime + schedule.duration;
        if (block.timestamp >= vestedTime) {
            return schedule.totalAmount;
        }

        // Linear vesting between cliff and end
        uint256 timeVested = block.timestamp - schedule.startTime;
        return (schedule.totalAmount * timeVested) / schedule.duration;
    }

    /**
     * @dev Calculate releasable amount (vested - released)
     */
    function getReleasableAmount(bytes32 scheduleId)
        public
        view
        validSchedule(scheduleId)
        returns (uint256)
    {
        if (vestingSchedules[scheduleId].revoked) {
            return 0;
        }

        uint256 vested = getVestedAmount(scheduleId);
        uint256 released = vestingSchedules[scheduleId].releasedAmount;

        return vested > released ? vested - released : 0;
    }

    /**
     * @dev Get schedule details
     */
    function getSchedule(bytes32 scheduleId)
        external
        view
        validSchedule(scheduleId)
        returns (VestingSchedule memory)
    {
        return vestingSchedules[scheduleId];
    }

    /**
     * @dev Get all schedules for a beneficiary
     */
    function getBeneficiarySchedules(address beneficiary)
        external
        view
        returns (bytes32[] memory)
    {
        return beneficiarySchedules[beneficiary];
    }

    /**
     * @dev Get total releasable for beneficiary
     */
    function getTotalReleasable(address beneficiary)
        external
        view
        returns (uint256)
    {
        bytes32[] storage schedules = beneficiarySchedules[beneficiary];
        uint256 total = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            total += getReleasableAmount(schedules[i]);
        }

        return total;
    }

    /**
     * @dev Get schedule count
     */
    function getScheduleCount() external view returns (uint256) {
        return scheduleIds.length;
    }
}
