// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract LXONWrapper is ERC20, AccessControl {
    string public constant NAME = "LXON Wrapped";
    string public constant SYMBOL = "wLXON";
    uint8 public constant DECIMALS = 6;
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Reference to original LXON contract on LXON network
    address public originalLXON;
    
    event Wrapped(address indexed from, uint256 amount);
    event Unwrapped(address indexed to, uint256 amount);
    
    constructor(address _originalLXON) ERC20("LXON Wrapped", "wLXON") {
        originalLXON = _originalLXON;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }
    
    function wrap(uint256 amount) external {
        _mint(msg.sender, amount);
        emit Wrapped(msg.sender, amount);
    }
    
    function unwrap(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Unwrapped(msg.sender, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
    
    function burnFrom(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(account, amount);
    }
}
