// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA, address tokenB,
        uint amountADesired, uint amountBDesired,
        uint amountAMin, uint amountBMin,
        address to, uint deadline
    ) external returns (uint, uint, uint);
}

interface IUniswapV2Pair {
    function transfer(address to, uint value) external returns (bool);
}

/**
 * LiquidityBootstrap
 * ------------------
 * Deploys initial DEX liquidity with **permanently locked LP tokens**.
 * The LP tokens are sent to this contract, and the contract has no
 * withdraw function. This is the strongest signal of long-term commitment.
 *
 * Uses Uniswap V2-style router (works with Uniswap, Sushi, Pancake).
 */
contract LiquidityBootstrap is Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;
    IERC20 public immutable quote;      // USDC, WETH, etc.
    address public immutable router;
    address public lpToken;             // set after first addLiquidity
    uint256 public totalLpLocked;
    uint64  public deployedAt;

    event LiquidityDeployed(uint256 lxonAmount, uint256 quoteAmount, uint256 lpReceived);
    event LpLocked(uint256 amount);

    constructor(address _lxon, address _quote, address _router) Ownable(msg.sender) {
        lxon = IERC20(_lxon);
        quote = IERC20(_quote);
        router = _router;
    }

    /**
     * @notice Deploy initial liquidity. Caller must have approved both tokens.
     *         LP tokens are permanently locked in this contract.
     */
    function deployLiquidity(
        uint256 lxonAmount,
        uint256 quoteAmount,
        uint256 minLxon,
        uint256 minQuote
    ) external onlyOwner returns (uint256 lpAmount) {
        require(deployedAt == 0, "already deployed");

        lxon.safeTransferFrom(msg.sender, address(this), lxonAmount);
        quote.safeTransferFrom(msg.sender, address(this), quoteAmount);

        lxon.forceApprove(router, lxonAmount);
        quote.forceApprove(router, quoteAmount);

        (,, lpAmount) = IUniswapV2Router02(router).addLiquidity(
            address(lxon), address(quote),
            lxonAmount, quoteAmount,
            minLxon, minQuote,
            address(this),
            block.timestamp + 300
        );

        deployedAt = uint64(block.timestamp);
        totalLpLocked = lpAmount;

        emit LiquidityDeployed(lxonAmount, quoteAmount, lpAmount);
        emit LpLocked(lpAmount);
    }

    /// @notice No withdraw function. LP tokens are stuck here forever.
    function lockedLp() external view returns (uint256) { return totalLpLocked; }
}
