// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniswapV2Router02 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function WETH() external pure returns (address);
}

/**
 * LXONBuybackVault
 * ----------------
 * Receives LXON from RevenueSplitter and executes programmatic buyback & burn.
 *
 * Two modes:
 *   1. Direct burn  — burn LXON from the vault (when buyback isn't economical)
 *   2. Market buy   — swap LXON → WETH → LXON (unlikely direction) is wrong;
 *                     the actual pattern is: treasury receives OTHER tokens (USDC)
 *                     and swaps USDC → LXON then burns LXON.
 *
 * Since RevenueSplitter routes LXON, we burn it directly.
 * If the treasury ever holds USDC, call `buyAndBurn(usdcAmount)`.
 */
contract LXONBuybackVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public router;              // Uniswap V2-style router
    address public quoteToken;          // e.g. USDC

    uint256 public totalBurned;
    uint256 public totalBought;         // LXON acquired via market purchases

    event Burned(address indexed caller, uint256 amount);
    event BoughtAndBurned(uint256 quoteIn, uint256 lxonOut, uint256 burned);

    error NotConfigured();
    error ZeroAmount();

    constructor(address _lxon) Ownable(msg.sender) {
        if (_lxon == address(0)) revert NotConfigured();
        lxon = IERC20(_lxon);
    }

    /// @notice Called by RevenueSplitter — burn LXON directly.
    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        lxon.safeTransferFrom(msg.sender, address(this), amount);
        lxon.safeTransfer(burnAddress, amount);
        totalBurned += amount;
        emit Burned(msg.sender, amount);
    }

    /// @notice Swap quote token → LXON → burn. Requires router config.
    function buyAndBurn(uint256 quoteIn, uint256 minLxonOut) external nonReentrant {
        if (router == address(0) || quoteToken == address(0)) revert NotConfigured();
        if (quoteIn == 0) revert ZeroAmount();

        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteIn);
        IERC20(quoteToken).forceApprove(router, quoteIn);

        address[] memory path = new address[](2);
        path[0] = quoteToken;
        path[1] = address(lxon);

        uint256 before = lxon.balanceOf(address(this));
        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            quoteIn, minLxonOut, path, address(this), block.timestamp + 300
        );
        uint256 received = lxon.balanceOf(address(this)) - before;

        lxon.safeTransfer(burnAddress, received);
        totalBought += received;
        totalBurned += received;

        emit BoughtAndBurned(quoteIn, received, received);
    }

    function setRouter(address _router, address _quoteToken) external onlyOwner {
        router = _router;
        quoteToken = _quoteToken;
    }

    function setBurnAddress(address b) external onlyOwner {
        require(b != address(0), "burn addr");
        burnAddress = b;
    }
}
