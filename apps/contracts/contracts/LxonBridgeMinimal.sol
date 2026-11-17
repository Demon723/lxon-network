// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LxonBridgeMinimal
 * @notice Minimal cross-chain bridge for LXON tokens
 * @dev Simplified version with admin control, no complex validation
 */
contract LxonBridgeMinimal is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public chainId;
    address public admin;
    address public peerBridge;
    address public lxonToken;
    
    uint256 public dailyLimit;
    uint256 public dailyTransferred;
    uint256 public lastResetTime;
    
    bool public paused;
    
    // Transfer status
    enum TransferStatus { Pending, Approved, Rejected, Completed }
    
    struct Transfer {
        bytes32 id;
        uint256 fromChainId;
        uint256 toChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        uint256 timestamp;
        TransferStatus status;
    }
    
    mapping(bytes32 => Transfer) public transfers;
    mapping(address => bool) public supportedTokens;
    
    event TransferInitiated(
        bytes32 indexed transferId,
        uint256 fromChainId,
        uint256 toChainId,
        address indexed token,
        uint256 amount,
        address indexed sender,
        address recipient
    );
    
    event TransferApproved(bytes32 indexed transferId, address indexed approver);
    event TransferRejected(bytes32 indexed transferId, address indexed approver);
    event TransferCompleted(bytes32 indexed transferId, address indexed recipient);
    
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event PeerBridgeSet(address indexed peerBridge);
    event DailyLimitUpdated(uint256 newLimit);
    event Paused(bool status);
    
    constructor(uint256 _chainId) Ownable(msg.sender) {
        chainId = _chainId;
        admin = msg.sender;
        dailyLimit = 1000000 * 1e18; // 1M tokens default
        lastResetTime = block.timestamp;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }
    
    // Admin functions
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }
    
    function setPeerBridge(address _peerBridge) external onlyAdmin {
        peerBridge = _peerBridge;
        emit PeerBridgeSet(_peerBridge);
    }
    
    function setLxonToken(address _lxonToken) external onlyAdmin {
        lxonToken = _lxonToken;
    }
    
    function addToken(address _token) external onlyAdmin {
        supportedTokens[_token] = true;
        emit TokenAdded(_token);
    }
    
    function removeToken(address _token) external onlyAdmin {
        supportedTokens[_token] = false;
        emit TokenRemoved(_token);
    }
    
    function setDailyLimit(uint256 _limit) external onlyAdmin {
        dailyLimit = _limit;
        emit DailyLimitUpdated(_limit);
    }
    
    function setPaused(bool _paused) external onlyAdmin {
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
        require(supportedTokens[_token], "Token not supported");
        require(_amount > 0, "Amount must be > 0");
        require(peerBridge != address(0), "Peer bridge not set");
        
        // Check daily limit
        _resetDailyIfNeeded();
        require(dailyTransferred + _amount <= dailyLimit, "Daily limit exceeded");
        
        // Transfer tokens to bridge
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        
        // Create transfer record
        bytes32 transferId = keccak256(
            abi.encodePacked(
                chainId,
                _toChainId,
                _token,
                _amount,
                msg.sender,
                _recipient,
                block.timestamp
            )
        );
        
        transfers[transferId] = Transfer({
            id: transferId,
            fromChainId: chainId,
            toChainId: _toChainId,
            token: _token,
            amount: _amount,
            sender: msg.sender,
            recipient: _recipient,
            timestamp: block.timestamp,
            status: TransferStatus.Pending
        });
        
        dailyTransferred += _amount;
        
        emit TransferInitiated(transferId, chainId, _toChainId, _token, _amount, msg.sender, _recipient);
        
        return transferId;
    }
    
    // Admin approval for incoming transfers
    function approveTransfer(bytes32 _transferId) external onlyAdmin {
        Transfer storage transfer = transfers[_transferId];
        require(transfer.id == _transferId, "Transfer not found");
        require(transfer.status == TransferStatus.Pending, "Invalid status");
        require(transfer.toChainId == chainId, "Wrong chain");
        
        transfer.status = TransferStatus.Approved;
        emit TransferApproved(_transferId, msg.sender);
    }
    
    function rejectTransfer(bytes32 _transferId) external onlyAdmin {
        Transfer storage transfer = transfers[_transferId];
        require(transfer.id == _transferId, "Transfer not found");
        require(transfer.status == TransferStatus.Pending, "Invalid status");
        
        transfer.status = TransferStatus.Rejected;
        emit TransferRejected(_transferId, msg.sender);
    }
    
    function completeTransfer(bytes32 _transferId) external nonReentrant {
        Transfer storage transfer = transfers[_transferId];
        require(transfer.id == _transferId, "Transfer not found");
        require(transfer.status == TransferStatus.Approved, "Not approved");
        require(transfer.toChainId == chainId, "Wrong chain");
        
        transfer.status = TransferStatus.Completed;
        
        // Transfer tokens to recipient
        IERC20(transfer.token).safeTransfer(transfer.recipient, transfer.amount);
        
        emit TransferCompleted(_transferId, transfer.recipient);
    }
    
    // Emergency functions
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
    
    // Internal functions
    function _resetDailyIfNeeded() internal {
        if (block.timestamp >= lastResetTime + 1 days) {
            dailyTransferred = 0;
            lastResetTime = block.timestamp;
        }
    }
    
    // View functions
    function getTransfer(bytes32 _transferId) external view returns (Transfer memory) {
        return transfers[_transferId];
    }
}
