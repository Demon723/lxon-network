// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PriceOracle
 * @dev Price oracle for DEX with Chainlink integration and fallback pricing
 */
contract PriceOracle is Ownable(msg.sender), Pausable {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint8 decimals;
    }

    mapping(address => PriceData) public prices;
    mapping(address => address) public priceFeeds; // Chainlink price feed addresses

    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;
    uint256 public constant PRICE_PRECISION = 1e18;

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner(), "Not authorized");
        _;
    }

    function setPriceFeed(address token, address priceFeed) external onlyOwner whenNotPaused {
        require(token != address(0), "Invalid token");
        require(priceFeed != address(0), "Invalid price feed");
        priceFeeds[token] = priceFeed;
        emit PriceFeedUpdated(token, priceFeed);
    }

    function updatePrice(address token, uint256 price, uint8 decimals) external onlyOwner whenNotPaused {
        require(token != address(0), "Invalid token");
        require(price > 0, "Invalid price");
        
        prices[token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            decimals: decimals
        });
        
        emit PriceUpdated(token, price, block.timestamp);
    }

    function getPrice(address token) external view whenNotPaused returns (uint256 price, uint256 timestamp, bool isStale) {
        PriceData memory data = prices[token];
        require(data.price > 0, "Price not set");
        
        isStale = (block.timestamp - data.timestamp) > PRICE_STALENESS_THRESHOLD;
        require(!isStale, "Price is stale");
        return (data.price, data.timestamp, isStale);
    }

    function getPriceInUSD(address token, uint256 amount) external view returns (uint256) {
        PriceData memory data = prices[token];
        require(data.price > 0, "Price not set");
        
        // Adjust for decimals
        uint256 adjustedPrice = data.price * PRICE_PRECISION / (10 ** data.decimals);
        return (amount * adjustedPrice) / PRICE_PRECISION;
    }

    function getPairPrice(address tokenA, address tokenB) external view returns (uint256) {
        PriceData memory dataA = prices[tokenA];
        PriceData memory dataB = prices[tokenB];
        
        require(dataA.price > 0 && dataB.price > 0, "Prices not set");
        
        // Calculate relative price: priceA / priceB
        uint256 priceA = dataA.price * PRICE_PRECISION / (10 ** dataA.decimals);
        uint256 priceB = dataB.price * PRICE_PRECISION / (10 ** dataB.decimals);
        
        return (priceA * PRICE_PRECISION) / priceB;
    }

    function isPriceFresh(address token) external view returns (bool) {
        PriceData memory data = prices[token];
        return (block.timestamp - data.timestamp) <= PRICE_STALENESS_THRESHOLD;
    }

    function batchUpdatePrices(
        address[] calldata tokens,
        uint256[] calldata newPrices,
        uint8[] calldata decimals
    ) external onlyOwner whenNotPaused {
        require(tokens.length == newPrices.length && tokens.length == decimals.length, "Length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[tokens[i]] = PriceData({
                price: newPrices[i],
                timestamp: block.timestamp,
                decimals: decimals[i]
            });
            emit PriceUpdated(tokens[i], newPrices[i], block.timestamp);
        }
    }

    function pauseOracle() external onlyOwner {
        _pause();
    }

    function unpauseOracle() external onlyOwner {
        _unpause();
    }
}
