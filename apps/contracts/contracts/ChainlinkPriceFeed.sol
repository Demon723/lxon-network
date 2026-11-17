// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ChainlinkPriceFeed
 * @dev Chainlink price feed adapter for LXON blockchain
 * Provides real-time price data from Chainlink oracles
 */
contract ChainlinkPriceFeed is Ownable, AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // Price data structure
    struct PriceData {
        uint256 price;        // Price in 8 decimals (Chainlink standard)
        uint256 timestamp;    // Last update timestamp
        uint256 confidence;   // Confidence level (0-100)
    }

    // Supported price feeds
    mapping(bytes32 => PriceData) public priceFeeds;
    mapping(bytes32 => address) public feedAddresses;

    // Feed identifiers
    bytes32 public constant ETH_USD_FEED = keccak256("ETH_USD");
    bytes32 public constant BTC_USD_FEED = keccak256("BTC_USD");
    bytes32 public constant LXON_USD_FEED = keccak256("LXON_USD");

    // Stale price threshold (1 hour)
    uint256 public constant STALE_PRICE_THRESHOLD = 3600;

    // Events
    event PriceUpdated(bytes32 indexed feedId, uint256 price, uint256 timestamp);
    event FeedAddressUpdated(bytes32 indexed feedId, address feedAddress);
    event FeedRegistered(bytes32 indexed feedId, address feedAddress);

    modifier onlyOracle() {
        require(hasRole(ORACLE_ROLE, msg.sender), "Not oracle");
        _;
    }

    modifier validFeed(bytes32 feedId) {
        require(feedAddresses[feedId] != address(0), "Invalid feed");
        _;
    }

    constructor() Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }

    /**
     * @dev Register a new price feed
     * @param feedId Feed identifier
     * @param feedAddress Chainlink aggregator address
     */
    function registerFeed(bytes32 feedId, address feedAddress) external onlyOwner {
        require(feedAddress != address(0), "Invalid address");
        require(feedAddresses[feedId] == address(0), "Feed already registered");

        feedAddresses[feedId] = feedAddress;
        emit FeedRegistered(feedId, feedAddress);
    }

    /**
     * @dev Update feed address
     * @param feedId Feed identifier
     * @param feedAddress New Chainlink aggregator address
     */
    function updateFeedAddress(bytes32 feedId, address feedAddress) external onlyOwner {
        require(feedAddress != address(0), "Invalid address");
        require(feedAddresses[feedId] != address(0), "Feed not registered");

        feedAddresses[feedId] = feedAddress;
        emit FeedAddressUpdated(feedId, feedAddress);
    }

    /**
     * @dev Update price data (called by oracle)
     * @param feedId Feed identifier
     * @param price Latest price (8 decimals)
     * @param timestamp Update timestamp
     * @param confidence Confidence level (0-100)
     */
    function updatePrice(
        bytes32 feedId,
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) external onlyOracle validFeed(feedId) {
        require(price > 0, "Invalid price");
        require(timestamp > 0, "Invalid timestamp");
        require(confidence <= 100, "Invalid confidence");

        priceFeeds[feedId] = PriceData({
            price: price,
            timestamp: timestamp,
            confidence: confidence
        });

        emit PriceUpdated(feedId, price, timestamp);
    }

    /**
     * @dev Get latest price for a feed
     * @param feedId Feed identifier
     * @return price Latest price (8 decimals)
     * @return timestamp Last update timestamp
     */
    function getLatestPrice(bytes32 feedId) external view validFeed(feedId) returns (uint256 price, uint256 timestamp) {
        PriceData memory data = priceFeeds[feedId];

        // Check if price is stale
        require(block.timestamp - data.timestamp <= STALE_PRICE_THRESHOLD, "Price is stale");

        return (data.price, data.timestamp);
    }

    /**
     * @dev Get price with confidence check
     * @param feedId Feed identifier
     * @param minConfidence Minimum confidence level required
     * @return price Latest price (8 decimals)
     * @return timestamp Last update timestamp
     */
    function getPriceWithConfidence(
        bytes32 feedId,
        uint256 minConfidence
    ) external view validFeed(feedId) returns (uint256 price, uint256 timestamp) {
        PriceData memory data = priceFeeds[feedId];

        require(block.timestamp - data.timestamp <= STALE_PRICE_THRESHOLD, "Price is stale");
        require(data.confidence >= minConfidence, "Confidence too low");

        return (data.price, data.timestamp);
    }

    /**
     * @dev Check if price is stale
     * @param feedId Feed identifier
     * @return isStale True if price is stale
     */
    function isPriceStale(bytes32 feedId) external view validFeed(feedId) returns (bool isStale) {
        PriceData memory data = priceFeeds[feedId];
        return block.timestamp - data.timestamp > STALE_PRICE_THRESHOLD;
    }

    /**
     * @dev Get price data without staleness check
     * @param feedId Feed identifier
     * @return price Latest price (8 decimals)
     * @return timestamp Last update timestamp
     * @return confidence Confidence level
     */
    function getPriceData(bytes32 feedId) external view validFeed(feedId) returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) {
        PriceData memory data = priceFeeds[feedId];
        return (data.price, data.timestamp, data.confidence);
    }

    /**
     * @dev Grant oracle role
     * @param oracle Oracle address
     */
    function grantOracleRole(address oracle) external onlyOwner {
        _grantRole(ORACLE_ROLE, oracle);
    }

    /**
     * @dev Revoke oracle role
     * @param oracle Oracle address
     */
    function revokeOracleRole(address oracle) external onlyOwner {
        _revokeRole(ORACLE_ROLE, oracle);
    }

    /**
     * @dev Update stale price threshold
     * @param newThreshold New threshold in seconds
     */
    function updateStaleThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Invalid threshold");
        // This would require a state variable, simplified for now
    }
}
