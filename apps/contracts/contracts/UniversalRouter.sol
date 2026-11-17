// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DEXFactory.sol";
import "./Pair.sol";

/**
 * @title UniversalRouter
 * @dev Universal router for DEX with factory - supports any token pair
 */
contract UniversalRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    DEXFactory public factory;
    address public weth;

    uint256 public constant FEE_RATE = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    event PairCreated(address indexed token0, address indexed token1, address pair);
    event LiquidityAdded(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed pair, uint256 amountIn, uint256 amountOut);

    constructor(address _factory, address _weth) Ownable(msg.sender) {
        require(_factory != address(0) && _weth != address(0), "Invalid addresses");
        factory = DEXFactory(_factory);
        weth = _weth;
    }

    // ========== PAIR CREATION ==========

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = factory.createPair(tokenA, tokenB);
        emit PairCreated(tokenA, tokenB, pair);
    }

    // ========== LIQUIDITY FUNCTIONS ==========

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "Expired");

        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountBDesired);

        liquidity = Pair(pair).mint(to);

        (uint256 reserve0, uint256 reserve1,) = Pair(pair).getReserves();
        amountA = IERC20(tokenA).balanceOf(pair) - reserve0;
        amountB = IERC20(tokenB).balanceOf(pair) - reserve1;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage exceeded");

        emit LiquidityAdded(msg.sender, pair, amountA, amountB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "Expired");

        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        Pair(pair).transferFrom(msg.sender, pair, liquidity);

        (amountA, amountB) = Pair(pair).burn(to);

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage exceeded");

        emit LiquidityRemoved(msg.sender, pair, amountA, amountB, liquidity);
    }

    // ========== SWAP FUNCTIONS ==========

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Expired");
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        IERC20(tokenIn).safeTransferFrom(msg.sender, factory.getPair(tokenIn, path[1]), amountIn);

        // Simplified: only support direct swaps (2 tokens)
        require(path.length == 2, "Only direct swaps supported");

        address pair = factory.getPair(path[0], path[1]);
        require(pair != address(0), "Pair does not exist");

        (uint256 reserve0, uint256 reserve1,) = Pair(pair).getReserves();
        amounts[1] = Pair(pair).getAmountOut(amountIn, reserve0, reserve1);

        require(amounts[1] >= amountOutMin, "Slippage exceeded");

        Pair(pair).swap(amounts[1], 0, to);

        emit Swap(msg.sender, pair, amountIn, amounts[1]);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Expired");
        require(path.length == 2, "Only direct swaps supported");

        amounts = new uint256[](2);
        amounts[1] = amountOut;

        address pair = factory.getPair(path[0], path[1]);
        require(pair != address(0), "Pair does not exist");

        (uint256 reserve0, uint256 reserve1,) = Pair(pair).getReserves();
        amounts[0] = Pair(pair).getAmountOut(amountOut, reserve1, reserve0);

        require(amounts[0] <= amountInMax, "Exceeded max input");

        IERC20(path[0]).safeTransferFrom(msg.sender, pair, amounts[0]);
        Pair(pair).swap(amountOut, 0, to);

        emit Swap(msg.sender, pair, amounts[0], amountOut);
    }

    // ========== VIEW FUNCTIONS ==========

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return factory.getPair(tokenA, tokenB);
    }

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut) {
        address pair = factory.getPair(tokenIn, tokenOut);
        require(pair != address(0), "Pair does not exist");

        (uint256 reserve0, uint256 reserve1,) = Pair(pair).getReserves();
        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        if (tokenIn == token0) {
            amountOut = Pair(pair).getAmountOut(amountIn, reserve1, reserve0);
        } else {
            amountOut = Pair(pair).getAmountOut(amountIn, reserve0, reserve1);
        }
    }

    function getReserves(address tokenA, address tokenB) external view returns (uint256 reserveA, uint256 reserveB) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        (uint256 reserve0, uint256 reserve1,) = Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // ========== ADMIN FUNCTIONS ==========

    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid factory");
        factory = DEXFactory(_factory);
    }

    function setWETH(address _weth) external onlyOwner {
        require(_weth != address(0), "Invalid WETH");
        weth = _weth;
    }
}
