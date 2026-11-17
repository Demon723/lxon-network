// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./LXONValidatorStaking.sol";

/**
 * @title LXONSlashingContract
 * @dev Slashing conditions and penalties for LXON validators
 *      - Critical: 100% penalty (double signing, self-dealing)
 *      - Moderate: 10-50% penalty (extended downtime, repeated misses)
 *      - Minor: 1-10% penalty (occasional misses, latency issues)
 *      - Evidence-based slashing with dispute period
 */
contract LXONSlashingContract is AccessControl {
    // ============ Constants ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    // Slashing tiers
    uint256 public constant CRITICAL_SLASH = 10000;  // 100%
    uint256 public constant HIGH_SLASH = 5000;        // 50%
    uint256 public constant MEDIUM_SLASH = 2500;       // 25%
    uint256 public constant LOW_SLASH = 1000;         // 10%
    uint256 public constant MINIMAL_SLASH = 100;      // 1%

    // Dispute period (7 days to contest a slash)
    uint256 public constant DISPUTE_PERIOD = 7 * 24 * 60 * 60;

    // Evidence requirements
    uint256 public constant MIN_EVIDENCE_AGE = 1 hours;
    uint256 public constant MAX_EVIDENCE_AGE = 7 * 24 * 60 * 60;

    // ============ Structs ============
    struct SlashingRecord {
        uint256 id;
        address validator;
        uint256 penaltyTier;  // 1=minor, 2=moderate, 3=critical
        uint256 penaltyAmount;
        string slashType;
        string reason;
        bytes evidence;
        uint256 blockNumber;
        uint256 timestamp;
        bool disputed;
        bool executed;
    }

    struct Dispute {
        uint256 slashingEventId;
        address challenger;
        string reason;
        uint256 timestamp;
        bool resolved;
        bool successful;
    }

    // ============ State ============
    LXONValidatorStaking public validatorStaking;

    mapping(uint256 => SlashingRecord) public slashingEvents;
    uint256 public nextSlashingEventId;

    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public validatorSlashingHistory;

    // Global stats
    uint256 public totalSlashed;
    uint256 public totalCriticalSlashes;
    uint256 public totalModerateSlashes;
    uint256 public totalMinorSlashes;

    // ============ Events ============
    event SlashingInitiated(
        uint256 indexed eventId,
        address indexed validator,
        uint256 penaltyTier,
        string slashType,
        string reason
    );
    event SlashingExecuted(uint256 indexed eventId, address indexed validator, uint256 amount);
    event DisputeInitiated(uint256 indexed eventId, address indexed challenger, string reason);
    event DisputeResolved(uint256 indexed eventId, bool successful);
    event EvidenceSubmitted(uint256 indexed eventId, address indexed submitter, bytes evidence);

    // ============ Modifiers ============
    modifier onlyValidValidator(address _validator) {
        require(
            validatorStaking.getValidatorInfo(_validator).active,
            "LXONSlashingContract: validator not active"
        );
        _;
    }

    modifier onlyDisputable(uint256 _eventId) {
        require(!slashingEvents[_eventId].executed, "LXONSlashingContract: already executed");
        require(!slashingEvents[_eventId].disputed, "LXONSlashingContract: already disputed");
        require(
            block.timestamp < slashingEvents[_eventId].timestamp + DISPUTE_PERIOD,
            "LXONSlashingContract: dispute period expired"
        );
        _;
    }

    // ============ Constructor ============
    /**
     * @param _validatorStaking Address of validator staking contract
     */
    constructor(address _validatorStaking) {
        require(_validatorStaking != address(0), "LXONSlashingContract: invalid staking contract");

        validatorStaking = LXONValidatorStaking(_validatorStaking);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }

    // ============ Slashing Functions ============

    /**
     * @dev Initiate slashing for double signing (critical)
     * @param _validator Validator that double-signed
     * @param _blockNumber Block where double signing occurred
     * @param _evidence Evidence of double signing
     */
    function slashDoubleSigning(
        address _validator,
        uint256 _blockNumber,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        string memory slashType = "DOUBLE_SIGNING";
        string memory reason = "Validator signed conflicting blocks";
        _initiateSlashing(
            _validator,
            3,  // Critical tier
            CRITICAL_SLASH,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for self-dealing (critical)
     * @param _validator Validator that self-dealt
     * @param _evidence Evidence of self-dealing
     */
    function slashSelfDealing(
        address _validator,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        string memory slashType = "SELF_DEALING";
        string memory reason = "Validator engaged in self-dealing";
        _initiateSlashing(
            _validator,
            3,  // Critical tier
            CRITICAL_SLASH,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for extended downtime (moderate)
     * @param _validator Validator with extended downtime
     * @param _downtimeHours Hours of downtime
     * @param _evidence Evidence of downtime
     */
    function slashExtendedDowntime(
        address _validator,
        uint256 _downtimeHours,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        require(_downtimeHours >= 24, "LXONSlashingContract: downtime too short");

        uint256 penaltyPercent;
        if (_downtimeHours >= 168) {  // 7+ days
            penaltyPercent = HIGH_SLASH;  // 50%
        } else if (_downtimeHours >= 72) {  // 3-7 days
            penaltyPercent = MEDIUM_SLASH;  // 25%
        } else {  // 1-3 days
            penaltyPercent = LOW_SLASH;  // 10%
        }

        string memory slashType = "EXTENDED_DOWNTIME";
        string memory reason = string(abi.encodePacked("Downtime: ", _downtimeHours, " hours"));
        _initiateSlashing(
            _validator,
            2,  // Moderate tier
            penaltyPercent,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for repeated missed blocks (moderate)
     * @param _validator Validator with repeated misses
     * @param _missedBlocks Number of consecutive missed blocks
     * @param _evidence Evidence of missed blocks
     */
    function slashRepeatedMisses(
        address _validator,
        uint256 _missedBlocks,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        require(_missedBlocks >= 10, "LXONSlashingContract: too few misses");

        uint256 penaltyPercent;
        if (_missedBlocks >= 100) {
            penaltyPercent = HIGH_SLASH;  // 50%
        } else if (_missedBlocks >= 50) {
            penaltyPercent = MEDIUM_SLASH;  // 25%
        } else {
            penaltyPercent = LOW_SLASH;  // 10%
        }

        string memory slashType = "REPEATED_MISSES";
        string memory reason = string(abi.encodePacked("Missed blocks: ", _missedBlocks));
        _initiateSlashing(
            _validator,
            2,  // Moderate tier
            penaltyPercent,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for version lag (moderate)
     * @param _validator Validator not running latest version
     * @param _currentVersion Current required version
     * @param _validatorVersion Validator's version
     * @param _evidence Evidence of version lag
     */
    function slashVersionLag(
        address _validator,
        string calldata _currentVersion,
        string calldata _validatorVersion,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        string memory slashType = "VERSION_LAG";
        string memory reason = string(abi.encodePacked("Current: ", _currentVersion, ", Validator: ", _validatorVersion));
        _initiateSlashing(
            _validator,
            2,  // Moderate tier
            MEDIUM_SLASH,  // 25%
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for occasional missed blocks (minor)
     * @param _validator Validator with occasional misses
     * @param _missedBlocks Number of missed blocks
     * @param _evidence Evidence of missed blocks
     */
    function slashOccasionalMisses(
        address _validator,
        uint256 _missedBlocks,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        require(_missedBlocks >= 1 && _missedBlocks < 10, "LXONSlashingContract: invalid count");

        uint256 penaltyPercent = MINIMAL_SLASH + (_missedBlocks * 100);  // 1-10%

        string memory slashType = "OCCASIONAL_MISSES";
        string memory reason = string(abi.encodePacked("Missed blocks: ", _missedBlocks));
        _initiateSlashing(
            _validator,
            1,  // Minor tier
            penaltyPercent,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate slashing for latency issues (minor)
     * @param _validator Validator with high latency
     * @param _latencyMs Average latency in milliseconds
     * @param _evidence Evidence of latency
     */
    function slashLatency(
        address _validator,
        uint256 _latencyMs,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        require(_latencyMs > 1000, "LXONSlashingContract: latency too low");

        uint256 penaltyPercent;
        if (_latencyMs >= 5000) {
            penaltyPercent = LOW_SLASH;  // 10%
        } else if (_latencyMs >= 2000) {
            penaltyPercent = MINIMAL_SLASH * 5;  // 5%
        } else {
            penaltyPercent = MINIMAL_SLASH;  // 1%
        }

        string memory slashType = "HIGH_LATENCY";
        string memory reason = string(abi.encodePacked("Latency: ", _latencyMs, "ms"));
        _initiateSlashing(
            _validator,
            1,  // Minor tier
            penaltyPercent,
            slashType,
            reason,
            _evidence
        );
    }

    /**
     * @dev Initiate custom slashing (for exceptional cases)
     * @param _validator Validator to slash
     * @param _penaltyTier Penalty tier (1=minor, 2=moderate, 3=critical)
     * @param _penaltyPercent Custom penalty percentage
     * @param _slashType Type of slash
     * @param _reason Detailed reason
     * @param _evidence Evidence
     */
    function slashCustom(
        address _validator,
        uint256 _penaltyTier,
        uint256 _penaltyPercent,
        string calldata _slashType,
        string memory _reason,
        bytes calldata _evidence
    ) external onlyRole(ADMIN_ROLE) onlyValidValidator(_validator) {
        require(_penaltyTier >= 1 && _penaltyTier <= 3, "LXONSlashingContract: invalid tier");
        require(_penaltyPercent <= CRITICAL_SLASH, "LXONSlashingContract: penalty too high");

        _initiateSlashing(_validator, _penaltyTier, _penaltyPercent, _slashType, _reason, _evidence);
    }

    // ============ Dispute Resolution ============

    /**
     * @dev Initiate a dispute against a slashing event
     * @param _eventId Slashing event ID
     * @param _reason Reason for dispute
     */
    function initiateDispute(uint256 _eventId, string memory _reason) external onlyDisputable(_eventId) {
        require(slashingEvents[_eventId].validator != msg.sender, "LXONSlashingContract: cannot dispute self");

        disputes[_eventId] = Dispute({
            slashingEventId: _eventId,
            challenger: msg.sender,
            reason: _reason,
            timestamp: block.timestamp,
            resolved: false,
            successful: false
        });

        slashingEvents[_eventId].disputed = true;

        emit DisputeInitiated(_eventId, msg.sender, _reason);
    }

    /**
     * @dev Resolve a dispute
     * @param _eventId Slashing event ID
     * @param _successful Whether the dispute was successful
     */
    function resolveDispute(uint256 _eventId, bool _successful) external onlyRole(DISPUTE_RESOLVER_ROLE) {
        require(disputes[_eventId].timestamp > 0, "LXONSlashingContract: no dispute");
        require(!disputes[_eventId].resolved, "LXONSlashingContract: already resolved");

        disputes[_eventId].resolved = true;
        disputes[_eventId].successful = _successful;

        if (_successful) {
            // Cancel the slashing
            slashingEvents[_eventId].executed = false;
        } else {
            // Execute the slashing
            _executeSlashing(_eventId);
        }

        emit DisputeResolved(_eventId, _successful);
    }

    // ============ Execution ============

    /**
     * @dev Execute a slashing after dispute period expires
     * @param _eventId Slashing event ID
     */
    function executeSlashing(uint256 _eventId) external {
        require(!slashingEvents[_eventId].executed, "LXONSlashingContract: already executed");
        require(!slashingEvents[_eventId].disputed, "LXONSlashingContract: disputed");
        require(
            block.timestamp >= slashingEvents[_eventId].timestamp + DISPUTE_PERIOD,
            "LXONSlashingContract: dispute period not expired"
        );

        _executeSlashing(_eventId);
    }

    // ============ View Functions ============

    /**
     * @dev Get slashing event details
     * @param _eventId Event ID
     * @return Slashing event details
     */
    function getSlashingEvent(uint256 _eventId) external view returns (SlashingRecord memory) {
        return slashingEvents[_eventId];
    }

    /**
     * @dev Get dispute details
     * @param _eventId Event ID
     * @return Dispute details
     */
    function getDispute(uint256 _eventId) external view returns (Dispute memory) {
        return disputes[_eventId];
    }

    /**
     * @dev Get validator's slashing history
     * @param _validator Validator address
     * @return List of slashing event IDs
     */
    function getValidatorSlashingHistory(address _validator) external view returns (uint256[] memory) {
        return validatorSlashingHistory[_validator];
    }

    // ============ Internal Functions ============

    function _initiateSlashing(
        address _validator,
        uint256 _penaltyTier,
        uint256 _penaltyPercent,
        string memory _slashType,
        string memory _reason,
        bytes calldata _evidence
    ) internal {
        uint256 eventId = nextSlashingEventId++;

        slashingEvents[eventId] = SlashingRecord({
            id: eventId,
            validator: _validator,
            penaltyTier: _penaltyTier,
            penaltyAmount: 0,  // Calculated during execution
            slashType: _slashType,
            reason: _reason,
            evidence: _evidence,
            blockNumber: block.number,
            timestamp: block.timestamp,
            disputed: false,
            executed: false
        });

        validatorSlashingHistory[_validator].push(eventId);

        emit SlashingInitiated(eventId, _validator, _penaltyTier, _slashType, _reason);
    }

    function _executeSlashing(uint256 _eventId) internal {
        SlashingRecord storage slashingRecord = slashingEvents[_eventId];
        require(!slashingRecord.executed, "LXONSlashingContract: already executed");

        // Call validator staking contract to execute slash
        validatorStaking.slashValidator(
            slashingRecord.validator,
            slashingRecord.penaltyTier,
            slashingRecord.reason
        );

        slashingRecord.executed = true;

        // Update stats
        totalSlashed += slashingRecord.penaltyAmount;
        if (slashingRecord.penaltyTier == 3) {
            totalCriticalSlashes++;
        } else if (slashingRecord.penaltyTier == 2) {
            totalModerateSlashes++;
        } else {
            totalMinorSlashes++;
        }

        emit SlashingExecuted(_eventId, slashingRecord.validator, slashingRecord.penaltyAmount);
    }
}
