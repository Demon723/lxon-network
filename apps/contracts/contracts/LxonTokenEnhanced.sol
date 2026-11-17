// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LxonTokenEnhanced
 * @notice Enhanced ERC20 token for the LXON ecosystem with OpenZeppelin standards
 * 
 * Enhancements implemented:
 * 1. OpenZeppelin ERC20 with AccessControl (battle-tested)
 * 2. ERC2612 Permit for gasless approvals
 * 3. Timelock for admin functions (48-hour delay)
 * 4. Emergency stop with circuit breakers (per-function pausing)
 * 
 * Roles:
 *   DEFAULT_ADMIN_ROLE — can grant/revoke all other roles
 *   MINTER_ROLE        — can mint new supply (bridge, treasury)
 *   BURNER_ROLE        — can burn from any address (bridge)
 *   PAUSER_ROLE        — can pause/unpause specific functions
 *   TIMELOCK_ADMIN     — can schedule/cancel timelocked operations
 */
contract LxonTokenEnhanced is ERC20, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TIMELOCK_ADMIN = keccak256("TIMELOCK_ADMIN");

    // Circuit breaker flags
    bool public transfersPaused;
    bool public approvalsPaused;
    bool public mintingPaused;
    bool public burningPaused;

    // Timelock structure
    struct TimelockOperation {
        address target;
        bytes data;
        uint256 executeTime;
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 => TimelockOperation) public timelocks;
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    // Events for circuit breakers
    event CircuitBreakerTriggered(
        string functionType,
        bool paused,
        address indexed triggerer,
        uint256 timestamp
    );

    event TimelockScheduled(
        bytes32 indexed operationId,
        address indexed target,
        uint256 executeTime
    );

    event TimelockExecuted(
        bytes32 indexed operationId,
        address indexed executor
    );

    event TimelockCancelled(
        bytes32 indexed operationId,
        address indexed canceller
    );

    constructor(address admin, address initialHolder, uint256 initialSupply)
        ERC20("LXON", "LXON")
        ERC20Permit("LXON")
    {
        require(admin != address(0), "LXON: ZERO_ADMIN");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TIMELOCK_ADMIN, admin);
        _grantRole(PAUSER_ROLE, admin);

        if (initialSupply > 0 && initialHolder != address(0)) {
            _mint(initialHolder, initialSupply);
        }
    }

    /* --------------------------- Circuit Breakers --------------------------- */

    function triggerCircuitBreaker(
        bool _transfersPaused,
        bool _approvalsPaused,
        bool _mintingPaused,
        bool _burningPaused
    ) external onlyRole(PAUSER_ROLE) {
        transfersPaused = _transfersPaused;
        approvalsPaused = _approvalsPaused;
        mintingPaused = _mintingPaused;
        burningPaused = _burningPaused;

        emit CircuitBreakerTriggered(
            "GLOBAL",
            _transfersPaused || _approvalsPaused || _mintingPaused || _burningPaused,
            msg.sender,
            block.timestamp
        );
    }

    /* --------------------------- Transfers --------------------------- */

    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!transfersPaused, "LXON: TRANSFERS_PAUSED");
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!transfersPaused, "LXON: TRANSFERS_PAUSED");
        return super.transferFrom(from, to, value);
    }

    /* --------------------------- Approvals --------------------------- */

    function approve(address spender, uint256 value) public override returns (bool) {
        require(!approvalsPaused, "LXON: APPROVALS_PAUSED");
        return super.approve(spender, value);
    }

    /* --------------------------- Mint / Burn --------------------------- */

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(!mintingPaused, "LXON: MINTING_PAUSED");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(!burningPaused, "LXON: BURNING_PAUSED");
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        require(!burningPaused, "LXON: BURNING_PAUSED");
        _burn(from, amount);
    }

    /* --------------------------- Timelock --------------------------- */

    function scheduleTimelock(
        address target,
        bytes calldata data
    ) external onlyRole(TIMELOCK_ADMIN) returns (bytes32) {
        require(target != address(0), "LXON: ZERO_TARGET");
        require(data.length > 0, "LXON: EMPTY_DATA");

        uint256 executeTime = block.timestamp + TIMELOCK_DELAY;
        bytes32 operationId = keccak256(abi.encode(target, data, executeTime));

        require(timelocks[operationId].executeTime == 0, "LXON: TIMELOCK_EXISTS");

        timelocks[operationId] = TimelockOperation({
            target: target,
            data: data,
            executeTime: executeTime,
            executed: false,
            cancelled: false
        });

        emit TimelockScheduled(operationId, target, executeTime);
        return operationId;
    }

    function executeTimelock(bytes32 operationId) external onlyRole(TIMELOCK_ADMIN) {
        TimelockOperation storage op = timelocks[operationId];
        require(op.executeTime > 0, "LXON: TIMELOCK_NOT_FOUND");
        require(!op.executed, "LXON: TIMELOCK_EXECUTED");
        require(!op.cancelled, "LXON: TIMELOCK_CANCELLED");
        require(block.timestamp >= op.executeTime, "LXON: TIMELOCK_NOT_READY");

        op.executed = true;

        (bool success, ) = op.target.call(op.data);
        require(success, "LXON: TIMELOCK_EXECUTION_FAILED");

        emit TimelockExecuted(operationId, msg.sender);
    }

    function cancelTimelock(bytes32 operationId) external onlyRole(TIMELOCK_ADMIN) {
        TimelockOperation storage op = timelocks[operationId];
        require(op.executeTime > 0, "LXON: TIMELOCK_NOT_FOUND");
        require(!op.executed, "LXON: TIMELOCK_EXECUTED");
        require(!op.cancelled, "LXON: TIMELOCK_CANCELLED");

        op.cancelled = true;

        emit TimelockCancelled(operationId, msg.sender);
    }

    /* --------------------------- View Functions --------------------------- */

    function getTimelock(bytes32 operationId) external view returns (TimelockOperation memory) {
        return timelocks[operationId];
    }

    function isTimelockReady(bytes32 operationId) external view returns (bool) {
        TimelockOperation memory op = timelocks[operationId];
        return op.executeTime > 0 && !op.executed && !op.cancelled && block.timestamp >= op.executeTime;
    }
}
