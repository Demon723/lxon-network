// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Pair.sol";

contract Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IERC20 public immutable lxon;
    Pair public pair;

    uint256 public constant FEE_RATE = 30;
    uint256 public constant FEE_DENOMINATOR = 10000;

    event AddLiquidity(address indexed provider, uint256 amountLXON, uint256 amountWLXON, uint256 liquidity);
    event RemoveLiquidity(address indexed provider, uint256 amountLXON, uint256 amountWLXON, uint256 liquidity);
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, bool lxonToWeth);

    constructor(address _weth, address _lxon, address _pair) Ownable(msg.sender) {
        require(_weth != address(0) && _lxon != address(0) && _pair != address(0), "Router: INVALID_ADDRESS");
        weth = IERC20(_weth);
        lxon = IERC20(_lxon);
        pair = Pair(_pair);
    }

    function addLiquidity(
        uint256 amountLXONDesired,
        uint256 amountWLXONDesired,
        uint256 amountLXONMin,
        uint256 amountWLXONMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (
        uint256 amountLXON,
        uint256 amountWLXON,
        uint256 liquidity
    ) {
        require(block.timestamp <= deadline, "Router: EXPIRED");

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        // === FIRST LIQUIDITY (reserves are 0) ===
        if (reserve0 == 0 && reserve1 == 0) {
            amountLXON = amountLXONDesired;
            amountWLXON = amountWLXONDesired;
            _transferFrom(lxon, msg.sender, address(pair), amountLXON);
            _transferFrom(weth, msg.sender, address(pair), amountWLXON);
            liquidity = pair.mint(to);
            require(liquidity > 0, "Router: INSUFFICIENT_LIQUIDITY");
            emit AddLiquidity(msg.sender, amountLXON, amountWLXON, liquidity);
            return (amountLXON, amountWLXON, liquidity);
        }

        // === SUBSEQUENT LIQUIDITY (reserves exist) ===
        uint256 amountLXONOptimal = _quote(amountWLXONDesired, reserve1, reserve0);
        uint256 amountWLXONOptimal = _quote(amountLXONDesired, reserve0, reserve1);
        if (amountLXONOptimal <= amountLXONDesired) {
            require(amountLXONOptimal >= amountLXONMin, "Router: INSUFFICIENT_LXON_AMOUNT");
            amountLXON = amountLXONOptimal;
            amountWLXON = amountWLXONDesired;
        } else {
            require(amountWLXONOptimal >= amountWLXONMin, "Router: INSUFFICIENT_WLXON_AMOUNT");
            amountLXON = amountLXONDesired;
            amountWLXON = amountWLXONOptimal;
        }
            _transferFrom(lxon, msg.sender, address(pair), amountLXON);
        _transferFrom(weth, msg.sender, address(pair), amountWLXON);
        liquidity = pair.mint(to);
        emit AddLiquidity(msg.sender, amountLXON, amountWLXON, liquidity);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function removeLiquidity(
        uint256 liquidity,
        uint256 amountLXONMin,
        uint256 amountWLXONMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountLXON, uint256 amountWLXON) {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        require(liquidity > 0, "Router: INSUFFICIENT_LIQUIDITY");

        amountLXON = (liquidity * reserve0) / pair.totalSupply();
        amountWLXON = (liquidity * reserve1) / pair.totalSupply();
        require(amountLXON >= amountLXONMin, "Router: INSUFFICIENT_LXON_AMOUNT");
        require(amountWLXON >= amountWLXONMin, "Router: INSUFFICIENT_WLON_AMOUNT");

        pair.burn(to);
        weth.transfer(to, amountWLXON);
        lxon.transfer(to, amountLXON);

        emit RemoveLiquidity(msg.sender, amountLXON, amountWLXON, liquidity);
    }

    function swapLXONForWETH(
        uint256 amountLXONIn,
        uint256 amountWLXONOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountWLXONOut) {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        amountWLXONOut = pair.getAmountOut(amountLXONIn, reserve1, reserve0);
        require(amountWLXONOut >= amountWLXONOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        _transferFrom(lxon, msg.sender, address(pair), amountLXONIn);
        // pair.swap(amount0Out, amount1Out, to) - token0=WETH, token1=LXON
        // For LXON->WETH, we output WETH (token0), so amount0Out=amountWLXONOut, amount1Out=0
        pair.swap(amountWLXONOut, 0, to);
        emit Swap(msg.sender, amountLXONIn, amountWLXONOut, true);
    }

    function swapWETHForLXON(
        uint256 amountWLXONIn,
        uint256 amountLXONOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountLXONOut) {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        amountLXONOut = pair.getAmountOut(amountWLXONIn, reserve0, reserve1);
        require(amountLXONOut >= amountLXONOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        _transferFrom(weth, msg.sender, address(pair), amountWLXONIn);
        pair.swap(0, amountLXONOut, to);
        emit Swap(msg.sender, amountWLXONIn, amountLXONOut, false);
    }

    function _addLiquidity(uint256 amountLXON, uint256 amountWLXON) internal {
        _transferFrom(lxon, msg.sender, address(pair), amountLXON);
        _transferFrom(weth, msg.sender, address(pair), amountWLXON);
    }

    function _transferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        token.safeTransferFrom(from, to, amount);
    }

    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0 && reserveA > 0 && reserveB > 0, "Router: INVALID_VALUES");
        amountB = (amountA * reserveB) / reserveA;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");
        amountOut = (amountIn * (FEE_DENOMINATOR - FEE_RATE) * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountIn * (FEE_DENOMINATOR - FEE_RATE));
    }

    /**
     * @dev Generic swap function for price floor mechanism
     * Simplified for direct token swaps - delegates to existing swap functions
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        require(path.length == 2, "Router: ONLY_DIRECT_SWAPS_SUPPORTED");

        amounts = new uint256[](2);
        amounts[0] = amountIn;

        if (path[0] == address(weth) && path[1] == address(lxon)) {
            // WETH -> LXON - delegate to existing function
            amounts[1] = this.swapWETHForLXON(amountIn, amountOutMin, to, deadline);
        } else if (path[0] == address(lxon) && path[1] == address(weth)) {
            // LXON -> WETH - delegate to existing function
            amounts[1] = this.swapLXONForWETH(amountIn, amountOutMin, to, deadline);
        } else {
            revert("Router: UNSUPPORTED_TOKEN_PAIR");
        }

        return amounts;
    }
}
