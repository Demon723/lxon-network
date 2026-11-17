// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WETH9 is ERC20, ReentrancyGuard {
    event Deposit(address indexed sender, uint256 value);
    event Withdrawal(address indexed sender, uint256 value);

    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function deposit(address to) external payable {
        _mint(to, msg.value);
        emit Deposit(to, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(balanceOf(msg.sender) >= amount, "WETH9: insufficient balance");
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "WETH9: ETH transfer failed");
        emit Withdrawal(msg.sender, amount);
    }
}
