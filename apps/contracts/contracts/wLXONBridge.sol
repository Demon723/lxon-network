// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LXONWrapper.sol";

/**
 * @title wLXON Bridge - Destination Chain (Polygon)
 * @dev Mints/burns wLXON based on cross-chain messages
 */
contract wLXONBridge is AccessControl, Ownable {
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public wlxonToken;
    
    // Source chain ID (LXON = 724)
    uint256 public sourceChainId;
    
    // Cross-chain message tracking
    uint256 public nonce;
    mapping(uint256 => bool) public processedNonces;
    
    // Events
    event Minted(
        uint256 indexed nonce,
        address indexed to,
        uint256 amount
    );
    
    event Burned(
        uint256 indexed nonce,
        address indexed from,
        uint256 amount
    );

    constructor(address _wlxonToken, uint256 _sourceChainId) Ownable(msg.sender) {
        wlxonToken = IERC20(_wlxonToken);
        sourceChainId = _sourceChainId;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(RELAYER_ROLE, msg.sender);
    }

    /**
     * @dev Mint wLXON after bridging from LXON network
     * @param to Address to receive wLXON
     * @param amount Amount of wLXON to mint
     * @param _nonce Unique identifier from source chain
     */
    function mint(address to, uint256 amount, uint256 _nonce) external onlyRole(RELAYER_ROLE) {
        require(!processedNonces[_nonce], "Already processed");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        
        // Mark as processed
        processedNonces[_nonce] = true;
        
        // Mint wLXON (requires wLXON token to have mint function)
        try LXONWrapper(address(wlxonToken)).mint(to, amount) {
            // Success
        } catch {
            revert("Mint failed - check wLXON mint permission");
        }
        
        emit Minted(_nonce, to, amount);
    }

    /**
     * @dev Burn wLXON to bridge back to LXON network
     * @param amount Amount of wLXON to burn
     */
    function burn(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        
        // Transfer wLXON from user to bridge
        require(
            wlxonToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // Burn wLXON
        try LXONWrapper(address(wlxonToken)).burnFrom(address(this), amount) {
            // Success
        } catch {
            revert("Burn failed - check wLXON burn permission");
        }
        
        // Emit event for relayer to pick up
        emit Burned(nonce, msg.sender, amount);
        nonce++;
    }

    /**
     * @dev Set source chain ID
     */
    function setSourceChainId(uint256 _chainId) external onlyRole(ADMIN_ROLE) {
        sourceChainId = _chainId;
    }

    /**
     * @dev Update wLXON token address
     */
    function setWLXONToken(address _wlxonToken) external onlyRole(ADMIN_ROLE) {
        wlxonToken = IERC20(_wlxonToken);
    }

    /**
     * @dev Rescue stuck tokens
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }
}
