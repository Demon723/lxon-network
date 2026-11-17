// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Simple Wrapped LXON
 * @notice Simple ERC20 implementation for Geth v1.10.26 compatibility
 * @dev No OpenZeppelin dependencies to avoid mcopy instruction issues
 */
contract SimpleWrappedLXON {
    address public admin;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    string public name = "Wrapped LXON";
    string public symbol = "wLXON";
    uint8 public decimals = 18;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event AdminUpdated(address indexed newAdmin);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    // Admin mints after verifying a deposit on LXON Chain
    function mint(address to, uint256 amount) external onlyAdmin {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    // User can burn to redeem on LXON Chain
    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
        emit AdminUpdated(newAdmin);
    }
}
