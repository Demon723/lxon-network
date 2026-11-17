// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LxonBridge
 * @notice Simple cross-chain bridge with built-in validator management
 * @dev Simplified version of the backup bridge for gas efficiency
 */
contract LxonBridge is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct BridgeTransfer {
        bytes32 transferId;
        uint256 fromChainId;
        uint256 toChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        uint256 timestamp;
        TransferStatus status;
    }

    enum TransferStatus { Pending, Locked, Completed, Failed }

    event TransferInitiated(
        bytes32 indexed transferId,
        uint256 fromChainId,
        uint256 toChainId,
        address indexed token,
        uint256 amount,
        address indexed sender,
        address recipient
    );

    event TransferCompleted(
        bytes32 indexed transferId,
        address indexed recipient
    );

    event TransferFailed(
        bytes32 indexed transferId,
        string reason
    );

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event PeerBridgeSet(uint256 indexed chainId, address indexed bridge);
    event Paused(bool status);

    mapping(bytes32 => BridgeTransfer) public transfers;
    mapping(address => bool) public validators;
    mapping(uint256 => address) public peerBridges;
    
    uint256 public minConfirmations;
    uint256 public maxTransferAmount;
    bool public paused;

    modifier onlyValidator() {
        require(validators[msg.sender], "Not authorized validator");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor() Ownable(msg.sender) {
        minConfirmations = 1;
        maxTransferAmount = 1000000 * 1e18;
    }

    // Admin functions
    function addValidator(address _validator) external onlyOwner {
        require(!validators[_validator], "Already validator");
        validators[_validator] = true;
        emit ValidatorAdded(_validator);
    }

    function removeValidator(address _validator) external onlyOwner {
        validators[_validator] = false;
        emit ValidatorRemoved(_validator);
    }

    function setPeerBridge(uint256 _chainId, address _bridge) external onlyOwner {
        peerBridges[_chainId] = _bridge;
        emit PeerBridgeSet(_chainId, _bridge);
    }

    function setMinConfirmations(uint256 _minConfirmations) external onlyOwner {
        require(_minConfirmations > 0, "Invalid confirmations");
        minConfirmations = _minConfirmations;
    }

    function setMaxTransferAmount(uint256 _maxAmount) external onlyOwner {
        maxTransferAmount = _maxAmount;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    // User functions
    function initiateTransfer(
        address _token,
        uint256 _amount,
        uint256 _toChainId,
        address _recipient
    ) external nonReentrant whenNotPaused returns (bytes32) {
        require(_amount > 0, "Amount must be > 0");
        require(_amount <= maxTransferAmount, "Exceeds max amount");
        require(peerBridges[_toChainId] != address(0), "Chain not registered");

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
            status: TransferStatus.Locked
        });

        emit TransferInitiated(transferId, block.chainid, _toChainId, _token, _amount, msg.sender, _recipient);

        return transferId;
    }

    // Validator functions
    function completeTransfer(
        bytes32 _transferId,
        address _token,
        uint256 _amount,
        address _recipient
    ) external onlyValidator nonReentrant {
        BridgeTransfer storage transfer = transfers[_transferId];
        require(transfer.transferId == _transferId, "Transfer not found");
        require(transfer.status == TransferStatus.Pending, "Invalid status");
        require(transfer.toChainId == block.chainid, "Wrong chain");
        require(transfer.amount == _amount, "Amount mismatch");

        transfer.status = TransferStatus.Completed;

        IERC20(_token).safeTransfer(_recipient, _amount);

        emit TransferCompleted(_transferId, _recipient);
    }

    function createIncomingTransfer(
        bytes32 _transferId,
        uint256 _fromChainId,
        address _token,
        uint256 _amount,
        address _sender,
        address _recipient
    ) external onlyValidator {
        require(transfers[_transferId].transferId == bytes32(0), "Transfer exists");

        transfers[_transferId] = BridgeTransfer({
            transferId: _transferId,
            fromChainId: _fromChainId,
            toChainId: block.chainid,
            token: _token,
            amount: _amount,
            sender: _sender,
            recipient: _recipient,
            timestamp: block.timestamp,
            status: TransferStatus.Pending
        });
    }

    // Emergency functions
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    // View functions
    function getTransfer(bytes32 _transferId) external view returns (BridgeTransfer memory) {
        return transfers[_transferId];
    }
}
