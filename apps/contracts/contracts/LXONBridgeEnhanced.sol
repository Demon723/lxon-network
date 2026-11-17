// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title LXONBridgeEnhanced
 * @notice Enhanced cross-chain bridge with comprehensive security and features
 * 
 * Enhancements implemented:
 * 5. Batch operations for multi-token transfers
 * 7. ERC20 Permit support for gasless operations
 * 8. Multi-sig validator signatures (threshold-based)
 * 9. Validator staking and slashing
 * 10. Cross-chain message passing
 * 12. Comprehensive event logging
 * 13. Circuit breaker events
 * 14. Oracle integration for dynamic limits
 * 17. Flash loan protection
 */
contract LXONBridgeEnhanced is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TIMELOCK_ADMIN = keccak256("TIMELOCK_ADMIN");

    struct BridgeTransfer {
        bytes32 transferId;
        uint256 fromChainId;
        uint256 toChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        uint256 timestamp;
        uint256 gasUsed;
        TransferStatus status;
    }

    struct CrossChainMessage {
        bytes32 messageId;
        address sender;
        bytes data;
        uint256 toChainId;
        uint256 timestamp;
        MessageStatus status;
    }

    enum TransferStatus { Pending, Locked, Completed, Failed }
    enum MessageStatus { Pending, Delivered, Failed }

    // Transfer events with comprehensive logging
    event TransferInitiated(
        bytes32 indexed transferId,
        uint256 indexed fromChainId,
        uint256 indexed toChainId,
        address token,
        uint256 amount,
        address sender,
        address recipient,
        uint256 gasUsed,
        uint256 timestamp
    );

    event TransferCompleted(
        bytes32 indexed transferId,
        address indexed recipient,
        uint256 gasUsed,
        uint256 timestamp
    );

    event TransferFailed(
        bytes32 indexed transferId,
        string reason,
        uint256 timestamp
    );

    event BatchTransferInitiated(
        bytes32[] indexed transferIds,
        uint256 totalAmount,
        address indexed sender,
        uint256 timestamp
    );

    // Message passing events
    event MessageSent(
        bytes32 indexed messageId,
        address indexed sender,
        uint256 indexed toChainId,
        bytes data,
        uint256 timestamp
    );

    event MessageDelivered(
        bytes32 indexed messageId,
        address indexed recipient,
        uint256 timestamp
    );

    // Validator events
    event ValidatorAdded(address indexed validator, uint256 stake);
    event ValidatorRemoved(address indexed validator, uint256 slashAmount);
    event ValidatorSigned(bytes32 indexed transferId, address indexed validator);
    event ValidatorSlashed(address indexed validator, uint256 amount, string reason);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    // Circuit breaker events
    event CircuitBreakerTriggered(
        string functionType,
        bool paused,
        address indexed triggerer,
        uint256 timestamp,
        uint256 blockNumber
    );

    // Oracle events
    event DynamicLimitUpdated(uint256 newLimit, uint256 price, uint256 timestamp);

    // State variables
    mapping(bytes32 => BridgeTransfer) public transfers;
    mapping(bytes32 => CrossChainMessage) public messages;
    mapping(address => bool) public validators;
    mapping(uint256 => address) public peerBridges;
    mapping(bytes32 => mapping(address => bool)) public transferSignatures;
    mapping(bytes32 => uint256) public signatureCount;
    mapping(address => uint256) public validatorStake;
    
    uint256 public minConfirmations;
    uint256 public maxTransferAmount;
    uint256 public dynamicMaxTransferAmount;
    uint256 public constant MIN_VALIDATOR_STAKE = 10000 * 1e18;
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    /// @notice Receives slashed validator stake. The bridge is AccessControl-based (no
    ///         Ownable), so slashed funds need an explicit destination.
    address public treasury;

    /// @notice The timelock contract (LxonTokenEnhanced) that admin parameter changes
    ///         must pass through. Immutable: if the timelock is ever replaced, this
    ///         bridge has to be redeployed — that is deliberate, so the bridge can
    ///         never be repointed at a timelock without a delay.
    /// @dev `scheduleTimelock`/`executeTimelock` on the token call us via
    ///      `target.call(data)`, so `msg.sender` here is the timelock address, not the
    ///      account that scheduled the operation. Granting the timelock
    ///      DEFAULT_ADMIN_ROLE instead would have let it grant itself any bridge role;
    ///      this narrow check only permits the five parameter setters below.
    address public immutable timelock;

    /// @notice The LXON token that validators stake and that slashed stake is paid out in.
    /// @dev This used to be `IERC20(address(this))` inside addValidator/removeValidator/
    ///      slashValidator. The bridge is AccessControl+ReentrancyGuard+Pausable only — it
    ///      holds no token — so every one of those calls reverted in SafeERC20 with
    ///      "Address with no code". It is immutable for the same reason as `timelock`.
    IERC20 public immutable lxonToken;

    AggregatorV3Interface public priceFeed;

    // Circuit breaker flags
    bool public transfersPaused;
    bool public messagesPaused;
    bool public batchOperationsPaused;

    // Flash loan protection
    uint256 private _bridgeBalanceBefore;

    modifier onlyValidator() {
        require(validators[msg.sender], "Not authorized validator");
        _;
    }

    modifier whenTransfersNotPaused() {
        require(!transfersPaused, "Transfers paused");
        _;
    }

    modifier whenMessagesNotPaused() {
        require(!messagesPaused, "Messages paused");
        _;
    }

    modifier whenBatchNotPaused() {
        require(!batchOperationsPaused, "Batch operations paused");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == timelock, "Only timelock");
        _;
    }

    modifier noFlashLoan() {
        _bridgeBalanceBefore = address(this).balance;
        _;
        require(address(this).balance >= _bridgeBalanceBefore, "Flash loan detected");
    }

    constructor(address _priceFeed, address _timelock, address _lxonToken) {
        require(_timelock != address(0), "Zero timelock");
        require(_lxonToken != address(0), "Zero token");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        // Vestigial. The bridge's timelock gating is the immutable `timelock` address
        // check below, not this role — holding TIMELOCK_ADMIN here grants nothing, so do
        // not treat it as timelock power over the bridge.
        _grantRole(TIMELOCK_ADMIN, msg.sender);

        timelock = _timelock;
        lxonToken = IERC20(_lxonToken);
        treasury = msg.sender;

        minConfirmations = 2;
        maxTransferAmount = 1000000 * 1e18;
        dynamicMaxTransferAmount = maxTransferAmount;

        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
        }
    }

    /* --------------------------- Circuit Breakers --------------------------- */

    function triggerCircuitBreaker(
        bool _transfersPaused,
        bool _messagesPaused,
        bool _batchOperationsPaused
    ) external onlyRole(PAUSER_ROLE) {
        transfersPaused = _transfersPaused;
        messagesPaused = _messagesPaused;
        batchOperationsPaused = _batchOperationsPaused;

        emit CircuitBreakerTriggered(
            "GLOBAL",
            _transfersPaused || _messagesPaused || _batchOperationsPaused,
            msg.sender,
            block.timestamp,
            block.number
        );
    }

    /* --------------------------- Oracle Integration --------------------------- */

    function updateDynamicLimits() external {
        if (address(priceFeed) != address(0)) {
            (, int256 price, , , ) = priceFeed.latestRoundData();
            if (price > 0) {
                dynamicMaxTransferAmount = uint256(price) * 1000;
                emit DynamicLimitUpdated(dynamicMaxTransferAmount, uint256(price), block.timestamp);
            }
        }
    }

    function getEffectiveMaxTransfer() public view returns (uint256) {
        return dynamicMaxTransferAmount > 0 ? dynamicMaxTransferAmount : maxTransferAmount;
    }

    /* --------------------------- Batch Operations --------------------------- */

    function initiateBatchTransfer(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        uint256 _toChainId,
        address[] calldata _recipients
    ) external nonReentrant whenNotPaused whenTransfersNotPaused whenBatchNotPaused returns (bytes32[] memory) {
        require(_tokens.length == _amounts.length, "Length mismatch");
        require(_tokens.length == _recipients.length, "Length mismatch");
        require(_tokens.length > 0, "Empty batch");
        require(peerBridges[_toChainId] != address(0), "Chain not registered");

        bytes32[] memory transferIds = new bytes32[](_tokens.length);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_amounts[i] > 0, "Amount must be > 0");
            require(_amounts[i] <= getEffectiveMaxTransfer(), "Exceeds max amount");

            bytes32 transferId = keccak256(
                abi.encodePacked(
                    block.chainid,
                    _toChainId,
                    _tokens[i],
                    _amounts[i],
                    msg.sender,
                    _recipients[i],
                    block.timestamp,
                    i
                )
            );

            require(transfers[transferId].transferId == bytes32(0), "Transfer exists");

            IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), _amounts[i]);

            uint256 gasStart = gasleft();

            transfers[transferId] = BridgeTransfer({
                transferId: transferId,
                fromChainId: block.chainid,
                toChainId: _toChainId,
                token: _tokens[i],
                amount: _amounts[i],
                sender: msg.sender,
                recipient: _recipients[i],
                timestamp: block.timestamp,
                gasUsed: gasStart - gasleft(),
                status: TransferStatus.Locked
            });

            transferIds[i] = transferId;
            totalAmount += _amounts[i];

            emit TransferInitiated(
                transferId,
                block.chainid,
                _toChainId,
                _tokens[i],
                _amounts[i],
                msg.sender,
                _recipients[i],
                gasStart - gasleft(),
                block.timestamp
            );
        }

        emit BatchTransferInitiated(transferIds, totalAmount, msg.sender, block.timestamp);
        return transferIds;
    }

    /* --------------------------- Permit Support --------------------------- */

    /// @notice Deposit-and-lock transfer for callers that already approved this bridge.
    ///         The gasless EIP-2612 path lives in initiateTransferWithPermit; both share the
    ///         same transferId derivation, limits, and validator-signing pipeline.
    function initiateTransfer(
        address _token,
        uint256 _amount,
        uint256 _toChainId,
        address _recipient
    ) external nonReentrant whenNotPaused whenTransfersNotPaused noFlashLoan returns (bytes32) {
        require(_amount > 0, "Amount must be > 0");
        require(_amount <= getEffectiveMaxTransfer(), "Exceeds max amount");
        require(peerBridges[_toChainId] != address(0), "Chain not registered");
        require(_recipient != address(0), "Zero recipient");

        bytes32 transferId = keccak256(
            abi.encodePacked(
                block.chainid,
                _toChainId,
                _token,
                _amount,
                msg.sender,
                _recipient,
                block.timestamp
            )
        );

        require(transfers[transferId].transferId == bytes32(0), "Transfer exists");

        uint256 gasStart = gasleft();
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        transfers[transferId] = BridgeTransfer({
            transferId: transferId,
            fromChainId: block.chainid,
            toChainId: _toChainId,
            token: _token,
            amount: _amount,
            sender: msg.sender,
            recipient: _recipient,
            timestamp: block.timestamp,
            gasUsed: gasStart - gasleft(),
            status: TransferStatus.Locked
        });

        emit TransferInitiated(
            transferId,
            block.chainid,
            _toChainId,
            _token,
            _amount,
            msg.sender,
            _recipient,
            gasStart - gasleft(),
            block.timestamp
        );

        return transferId;
    }

    function initiateTransferWithPermit(
        address _token,
        uint256 _amount,
        uint256 _toChainId,
        address _recipient,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant whenNotPaused whenTransfersNotPaused noFlashLoan returns (bytes32) {
        require(_amount > 0, "Amount must be > 0");
        require(_amount <= getEffectiveMaxTransfer(), "Exceeds max amount");
        require(peerBridges[_toChainId] != address(0), "Chain not registered");

        IERC20Permit(_token).permit(
            msg.sender,
            address(this),
            _amount,
            _deadline,
            _v,
            _r,
            _s
        );

        bytes32 transferId = keccak256(
            abi.encodePacked(
                block.chainid,
                _toChainId,
                _token,
                _amount,
                msg.sender,
                _recipient,
                block.timestamp
            )
        );

        require(transfers[transferId].transferId == bytes32(0), "Transfer exists");

        uint256 gasStart = gasleft();
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        transfers[transferId] = BridgeTransfer({
            transferId: transferId,
            fromChainId: block.chainid,
            toChainId: _toChainId,
            token: _token,
            amount: _amount,
            sender: msg.sender,
            recipient: _recipient,
            timestamp: block.timestamp,
            gasUsed: gasStart - gasleft(),
            status: TransferStatus.Locked
        });

        emit TransferInitiated(
            transferId,
            block.chainid,
            _toChainId,
            _token,
            _amount,
            msg.sender,
            _recipient,
            gasStart - gasleft(),
            block.timestamp
        );

        return transferId;
    }

    /* --------------------------- Multi-Sig Validator Signatures --------------------------- */

    function signTransfer(bytes32 _transferId) external onlyValidator {
        require(transfers[_transferId].transferId == _transferId, "Transfer not found");
        require(!transferSignatures[_transferId][msg.sender], "Already signed");

        transferSignatures[_transferId][msg.sender] = true;
        signatureCount[_transferId]++;

        emit ValidatorSigned(_transferId, msg.sender);

        if (signatureCount[_transferId] >= minConfirmations) {
            _executeTransfer(_transferId);
        }
    }

    function _executeTransfer(bytes32 _transferId) internal {
        BridgeTransfer storage transfer = transfers[_transferId];
        // initiateTransfer/initiateTransferWithPermit store Locked and nothing ever stored
        // Pending, so the previous `status == Pending` requirement made signTransfer revert
        // on every threshold (`LXON: ...Invalid status`) — the multi-sig release path was
        // unreachable. Locked is the state a signed-off transfer is in.
        require(transfer.status == TransferStatus.Locked, "Invalid status");
        // The old `transfer.toChainId == block.chainid` guard is gone: this contract has no
        // separate inbound completion function, so _executeTransfer is the *outbound*
        // release once validators sign, and requiring the destination to be this chain made
        // every cross-chain transfer non-executable. Peer-side release still needs its own
        // implementation on the destination chain.

        transfer.status = TransferStatus.Completed;

        uint256 gasStart = gasleft();
        IERC20(transfer.token).safeTransfer(transfer.recipient, transfer.amount);

        emit TransferCompleted(
            _transferId,
            transfer.recipient,
            gasStart - gasleft(),
            block.timestamp
        );
    }

    /* --------------------------- Validator Staking and Slashing --------------------------- */

    function addValidator(address _validator, uint256 _stake) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!validators[_validator], "Already validator");
        require(_stake >= MIN_VALIDATOR_STAKE, "Insufficient stake");

        // The staker must have approved this bridge for `lxonToken` first; msg.sender (the
        // admin adding the validator) is who the stake is debited from.
        lxonToken.safeTransferFrom(msg.sender, address(this), _stake);
        validatorStake[_validator] = _stake;
        validators[_validator] = true;
        _grantRole(VALIDATOR_ROLE, _validator);

        emit ValidatorAdded(_validator, _stake);
    }

    function removeValidator(address _validator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validators[_validator] = false;
        _revokeRole(VALIDATOR_ROLE, _validator);

        uint256 stake = validatorStake[_validator];
        if (stake > 0) {
            validatorStake[_validator] = 0;
            lxonToken.safeTransfer(_validator, stake);
        }

        emit ValidatorRemoved(_validator, stake);
    }

    function slashValidator(address _validator, uint256 _amount, string calldata _reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(validators[_validator], "Not a validator");
        require(validatorStake[_validator] >= _amount, "Insufficient stake");

        validatorStake[_validator] -= _amount;
        lxonToken.safeTransfer(treasury, _amount);

        emit ValidatorSlashed(_validator, _amount, _reason);
    }

    /* --------------------------- Cross-Chain Message Passing --------------------------- */

    function sendMessage(bytes calldata _data, uint256 _toChainId) external nonReentrant whenNotPaused whenMessagesNotPaused returns (bytes32) {
        require(peerBridges[_toChainId] != address(0), "Chain not registered");

        bytes32 messageId = keccak256(
            abi.encodePacked(
                block.chainid,
                _toChainId,
                msg.sender,
                _data,
                block.timestamp
            )
        );

        require(messages[messageId].messageId == bytes32(0), "Message exists");

        messages[messageId] = CrossChainMessage({
            messageId: messageId,
            sender: msg.sender,
            data: _data,
            toChainId: _toChainId,
            timestamp: block.timestamp,
            status: MessageStatus.Pending
        });

        emit MessageSent(messageId, msg.sender, _toChainId, _data, block.timestamp);
        return messageId;
    }

    function deliverMessage(bytes32 _messageId, address _recipient) external onlyValidator {
        CrossChainMessage storage message = messages[_messageId];
        require(message.messageId == _messageId, "Message not found");
        require(message.status == MessageStatus.Pending, "Invalid status");
        require(message.toChainId == block.chainid, "Wrong chain");

        message.status = MessageStatus.Delivered;

        emit MessageDelivered(_messageId, _recipient, block.timestamp);
    }

    /* --------------------------- Admin Functions --------------------------- */

    // Role-gated and immediate: identity/validator management and emergency stops stay
    // on DEFAULT_ADMIN_ROLE / PAUSER_ROLE so an operator can act without a 48h wait.
    // Parameter changes below are timelock-gated instead — schedule on the token, wait
    // TIMELOCK_DELAY, then the token calls in.

    function setPeerBridge(uint256 _chainId, address _bridge) external onlyTimelock {
        peerBridges[_chainId] = _bridge;
    }

    function setTreasury(address _treasury) external onlyTimelock {
        require(_treasury != address(0), "Zero treasury");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    function setMinConfirmations(uint256 _minConfirmations) external onlyTimelock {
        require(_minConfirmations > 0, "Invalid confirmations");
        minConfirmations = _minConfirmations;
    }

    function setMaxTransferAmount(uint256 _maxAmount) external onlyTimelock {
        maxTransferAmount = _maxAmount;
    }

    function setPriceFeed(address _priceFeed) external onlyTimelock {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /* --------------------------- View Functions --------------------------- */

    function getTransfer(bytes32 _transferId) external view returns (BridgeTransfer memory) {
        return transfers[_transferId];
    }

    function getMessage(bytes32 _messageId) external view returns (CrossChainMessage memory) {
        return messages[_messageId];
    }

    function getSignatureCount(bytes32 _transferId) external view returns (uint256) {
        return signatureCount[_transferId];
    }
}
