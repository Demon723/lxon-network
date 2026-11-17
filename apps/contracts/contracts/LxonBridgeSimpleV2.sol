// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title LxonBridgeSimpleV2
 * @notice Simple trust-based bridge for LXON cross-chain transfers
 * @dev Admin-controlled bridge without complex signature verification
 */
contract LxonBridgeSimpleV2 is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    
    uint256 public chainId;
    address public admin;
    
    // Transfer tracking
    mapping(bytes32 => bool) public processedTransfers;
    mapping(bytes32 => bool) public approvedTransfers;
    uint256 public transferNonce;
    
    // Token configuration
    enum TokenMode { NONE, LOCK_UNLOCK, MINT_BURN }
    
    struct TokenConfig {
        TokenMode mode;
        bool enabled;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 dailyLimit;
        uint256 dailyUsed;
        uint256 dayStartedAt;
    }
    
    mapping(address => TokenConfig) public tokenConfigs;
    
    // Peer bridges
    mapping(uint256 => address) public peerBridges;
    
    // Pending transfers (for admin approval)
    struct PendingTransfer {
        bytes32 transferId;
        uint256 srcChainId;
        address token;
        uint256 amount;
        address recipient;
        address sender;
        uint256 timestamp;
        bool approved;
        bool rejected;
    }
    
    mapping(bytes32 => PendingTransfer) public pendingTransfers;
    bytes32[] public pendingTransferIds;
    
    event TransferInitiated(bytes32 indexed transferId, uint256 srcChainId, uint256 dstChainId, address token, uint256 amount, address recipient, address sender);
    event TransferApproved(bytes32 indexed transferId, address admin);
    event TransferRejected(bytes32 indexed transferId, address admin, string reason);
    event TransferCompleted(bytes32 indexed transferId, uint256 srcChainId, address token, uint256 amount, address recipient, address sender);
    event TokenConfigured(address indexed token, TokenMode mode, bool enabled);
    event PeerBridgeSet(uint256 indexed peerChainId, address peerBridge);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }
    
    constructor(uint256 chainId_) Ownable(msg.sender) ReentrancyGuard() Pausable() {
        chainId = chainId_;
        admin = msg.sender;
    }
    
    function setAdmin(address newAdmin) external onlyOwner {
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminUpdated(oldAdmin, newAdmin);
    }
    
    function configureToken(
        address token,
        TokenMode mode,
        bool enabled,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        require(mode != TokenMode.NONE, "INVALID_MODE");

        tokenConfigs[token] = TokenConfig({
            mode: mode,
            enabled: enabled,
            minAmount: minAmount,
            maxAmount: maxAmount,
            dailyLimit: dailyLimit,
            dailyUsed: 0,
            dayStartedAt: block.timestamp
        });

        emit TokenConfigured(token, mode, enabled);
    }
    
    function setPeerBridge(uint256 peerChainId, address peerBridge) external onlyOwner {
        require(peerBridge != address(0), "ZERO_PEER");
        peerBridges[peerChainId] = peerBridge;
        emit PeerBridgeSet(peerChainId, peerBridge);
    }
    
    function initiateTransfer(
        uint256 dstChainId,
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant whenNotPaused returns (bytes32) {
        require(peerBridges[dstChainId] != address(0), "NO_PEER");
        require(recipient != address(0), "BAD_RECIPIENT");

        TokenConfig storage cfg = tokenConfigs[token];
        require(cfg.enabled, "TOKEN_DISABLED");
        require(amount >= cfg.minAmount, "MIN_AMOUNT");
        require(amount <= cfg.maxAmount, "MAX_AMOUNT");

        _checkDailyLimit(cfg, amount);

        // Use nonce for consistent transferId across chains
        transferNonce++;
        bytes32 transferId = keccak256(
            abi.encodePacked(
                transferNonce,
                token,
                amount,
                recipient,
                msg.sender
            )
        );

        // Burn or lock tokens
        if (cfg.mode == TokenMode.MINT_BURN) {
            IERC20Mintable(token).burn(msg.sender, amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Create pending transfer for admin approval
        pendingTransfers[transferId] = PendingTransfer({
            transferId: transferId,
            srcChainId: chainId,
            token: token,
            amount: amount,
            recipient: recipient,
            sender: msg.sender,
            timestamp: block.timestamp,
            approved: false,
            rejected: false
        });
        pendingTransferIds.push(transferId);

        emit TransferInitiated(transferId, chainId, dstChainId, token, amount, recipient, msg.sender);
        return transferId;
    }
    
    function approveTransfer(bytes32 transferId) external onlyAdmin {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        require(transfer.transferId == transferId, "TRANSFER_NOT_FOUND");
        require(!transfer.approved && !transfer.rejected, "ALREADY_PROCESSED");
        
        transfer.approved = true;
        approvedTransfers[transferId] = true;
        
        emit TransferApproved(transferId, msg.sender);
    }
    
    function rejectTransfer(bytes32 transferId, string calldata reason) external onlyAdmin {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        require(transfer.transferId == transferId, "TRANSFER_NOT_FOUND");
        require(!transfer.approved && !transfer.rejected, "ALREADY_PROCESSED");
        
        transfer.rejected = true;
        
        // Refund tokens
        TokenConfig storage cfg = tokenConfigs[transfer.token];
        if (cfg.mode == TokenMode.MINT_BURN) {
            IERC20Mintable(transfer.token).mint(transfer.sender, transfer.amount);
        } else {
            IERC20(transfer.token).safeTransfer(transfer.sender, transfer.amount);
        }
        
        emit TransferRejected(transferId, msg.sender, reason);
    }
    
    function completeTransfer(
        bytes32 transferId
    ) external nonReentrant whenNotPaused {
        require(!processedTransfers[transferId], "ALREADY_PROCESSED");
        require(approvedTransfers[transferId], "NOT_APPROVED");

        PendingTransfer storage transfer = pendingTransfers[transferId];
        require(transfer.transferId == transferId, "TRANSFER_NOT_FOUND");

        TokenConfig storage cfg = tokenConfigs[transfer.token];
        require(cfg.enabled, "TOKEN_DISABLED");

        processedTransfers[transferId] = true;

        if (cfg.mode == TokenMode.MINT_BURN) {
            IERC20Mintable(transfer.token).mint(transfer.recipient, transfer.amount);
        } else {
            IERC20(transfer.token).safeTransfer(transfer.recipient, transfer.amount);
        }

        emit TransferCompleted(transferId, transfer.srcChainId, transfer.token, transfer.amount, transfer.recipient, msg.sender);
    }
    
    function _checkDailyLimit(TokenConfig storage cfg, uint256 amount) internal {
        if (cfg.dailyLimit == 0) return;
        if (block.timestamp >= cfg.dayStartedAt + 1 days) {
            cfg.dailyUsed = 0;
            cfg.dayStartedAt = block.timestamp;
        }
        require(cfg.dailyUsed + amount <= cfg.dailyLimit, "DAILY_LIMIT");
        cfg.dailyUsed += amount;
    }
    
    function getPendingTransfers() external view returns (bytes32[] memory) {
        return pendingTransferIds;
    }
    
    function getPendingTransfer(bytes32 transferId) external view returns (PendingTransfer memory) {
        return pendingTransfers[transferId];
    }
    
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function rescue(address token, address to, uint256 amount) external onlyOwner whenPaused {
        IERC20(token).safeTransfer(to, amount);
    }

    receive() external payable {}
}
