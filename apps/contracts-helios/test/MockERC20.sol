// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * MockERC20
 * ---------
 * Simple mintable ERC20 used by tests. Mirrors OpenZeppelin's TestERC20.
 */
contract MockERC20 is ERC20 {
    constructor() ERC20("MockLXON", "MLXON") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}