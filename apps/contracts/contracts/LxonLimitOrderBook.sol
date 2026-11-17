// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LxonLimitOrderBook
 * @notice Limit order book for LXON DEX trading
 */
contract LxonLimitOrderBook is Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct Order {
        uint256 id;
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        bool isBuy; // true = buy LXON, false = sell LXON
        bool filled;
        uint256 timestamp;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;

    address public immutable lxon;
    address public immutable usdc;
    address public immutable pair;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy
    );

    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 amountIn,
        uint256 amountOut
    );

    event OrderCancelled(uint256 indexed orderId, address indexed maker);

    modifier onlyExistingOrder(uint256 orderId) {
        require(orders[orderId].id == orderId, "ORDER_NOT_FOUND");
        _;
    }

    constructor(address _lxon, address _usdc, address _pair, address _owner) Ownable(_owner) {
        require(_lxon != address(0), "ZERO_LXON");
        require(_usdc != address(0), "ZERO_USDC");
        require(_pair != address(0), "ZERO_PAIR");
        lxon = _lxon;
        usdc = _usdc;
        pair = _pair;
    }

    /**
     * @notice Create a limit order
     * @param tokenIn Token to sell
     * @param tokenOut Token to buy
     * @param amountIn Amount to sell
     * @param amountOut Amount to buy (minimum)
     * @param isBuy true = buy LXON, false = sell LXON
     */
    function createOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy
    ) external whenNotPaused returns (uint256 orderId) {
        require(tokenIn != address(0) && tokenOut != address(0), "INVALID_TOKEN");
        require(tokenIn != tokenOut, "SAME_TOKEN");
        require(amountIn > 0 && amountOut > 0, "ZERO_AMOUNT");
        require(
            (tokenIn == lxon || tokenIn == usdc) && (tokenOut == lxon || tokenOut == usdc),
            "INVALID_TOKEN_PAIR"
        );

        // Transfer tokens to contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            maker: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            isBuy: isBuy,
            filled: false,
            timestamp: block.timestamp
        });

        userOrders[msg.sender].push(orderId);

        emit OrderCreated(orderId, msg.sender, tokenIn, tokenOut, amountIn, amountOut, isBuy);
    }

    /**
     * @notice Fill a limit order
     * @param orderId Order to fill
     * @param amountIn Amount to provide
     */
    function fillOrder(uint256 orderId, uint256 amountIn) external whenNotPaused onlyExistingOrder(orderId) {
        Order storage order = orders[orderId];
        require(!order.filled, "ORDER_FILLED");
        require(msg.sender != order.maker, "CANNOT_FILL_OWN_ORDER");
        require(amountIn > 0, "ZERO_AMOUNT");
        require(amountIn <= order.amountIn, "EXCEEDS_ORDER_AMOUNT");

        // Calculate output amount
        uint256 amountOut = (amountIn * order.amountOut) / order.amountIn;

        // Transfer input from taker
        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer output to taker
        IERC20(order.tokenOut).safeTransfer(msg.sender, amountOut);

        // Return remaining input to maker
        if (amountIn < order.amountIn) {
            uint256 remaining = order.amountIn - amountIn;
            IERC20(order.tokenIn).safeTransfer(order.maker, remaining);
            order.amountIn = remaining;
        } else {
            order.filled = true;
        }

        emit OrderFilled(orderId, msg.sender, amountIn, amountOut);
    }

    /**
     * @notice Cancel an order
     * @param orderId Order to cancel
     */
    function cancelOrder(uint256 orderId) external onlyExistingOrder(orderId) {
        Order storage order = orders[orderId];
        require(msg.sender == order.maker, "NOT_MAKER");
        require(!order.filled, "ORDER_FILLED");

        // Return tokens to maker
        IERC20(order.tokenIn).safeTransfer(order.maker, order.amountIn);

        order.filled = true;

        emit OrderCancelled(orderId, msg.sender);
    }

    /**
     * @notice Get user's orders
     * @param user User address
     */
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    /**
     * @notice Get order details
     * @param orderId Order ID
     */
    function getOrder(uint256 orderId) external view returns (
        address maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy,
        bool filled,
        uint256 timestamp
    ) {
        Order memory order = orders[orderId];
        return (
            order.maker,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.amountOut,
            order.isBuy,
            order.filled,
            order.timestamp
        );
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
