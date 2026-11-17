// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title SimpleBridge
 * @notice Simplified bridge for single-chain testing (no approval required)
 */
contract SimpleBridge is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    
    uint256 public chainId;
    uint256 public transferNonce;
    bool public paused;
    
    enum TokenMode { NONE, LOCK_UNLOCK, MINT_BURN }
    
    struct TokenConfig {
        TokenMode mode;
        bool enabled;
        uint256 minAmount;
        uint256 maxAmount;
    }
    
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(uint256 => address) public peerBridges;
    mapping(bytes32 => bool) public processedTransfers;
    
    event TransferInitiated(bytes32 indexed transferId, uint256 srcChainId, uint256 dstChainId, address token, uint256 amount, address recipient);
    event TransferCompleted(bytes32 indexed transferId, uint256 srcChainId, address token, uint256 amount, address recipient);
    event TokenConfigured(address indexed token, TokenMode mode, bool enabled);
    event PeerBridgeSet(uint256 indexed peerChainId, address peerBridge);
    
    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }
    
    constructor(uint256 chainId_) Ownable(msg.sender) ReentrancyGuard() {
        chainId = chainId_;
        paused = false;
    }
    
    function configureToken(
        address token,
        TokenMode mode,
        bool enabled,
        uint256 minAmount,
        uint256 maxAmount
    ) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        require(mode != TokenMode.NONE, "INVALID_MODE");
        tokenConfigs[token] = TokenConfig(mode, enabled, minAmount, maxAmount);
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
        
        transferNonce++;
        bytes32 transferId = keccak256(abi.encodePacked(transferNonce, token, amount, recipient, msg.sender));
        
        if (cfg.mode == TokenMode.MINT_BURN) {
            IERC20Mintable(token).burn(msg.sender, amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        
        processedTransfers[transferId] = true;
        emit TransferInitiated(transferId, chainId, dstChainId, token, amount, recipient);
        return transferId;
    }
    
    function completeTransfer(
        bytes32 transferId,
        uint256 srcChainId,
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant {
        require(!processedTransfers[transferId], "ALREADY_PROCESSED");
        require(peerBridges[srcChainId] != address(0), "NO_PEER");
        require(recipient != address(0), "BAD_RECIPIENT");
        
        TokenConfig storage cfg = tokenConfigs[token];
        require(cfg.enabled, "TOKEN_DISABLED");
        
        processedTransfers[transferId] = true;
        
        if (cfg.mode == TokenMode.MINT_BURN) {
            IERC20Mintable(token).mint(recipient, amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
        
        emit TransferCompleted(transferId, srcChainId, token, amount, recipient);
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
    
    function rescue(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}
