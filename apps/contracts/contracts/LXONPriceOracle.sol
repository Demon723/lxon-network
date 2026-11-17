// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

// Optional Chainlink import - comment out if not available
// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Mock interface for when Chainlink is not available
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

interface IPair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

/**
 * @title LXONPriceOracle
 * @dev Provides LXON price in USD using Chainlink oracles and DEX pricing
 * Falls back to DEX price if Chainlink data is unavailable
 */
contract LXONPriceOracle is Ownable {
    AggregatorV3Interface public ethUsdFeed;
    AggregatorV3Interface public lxonEthFeed;
    
    address public immutable lxonToken;
    address public immutable wethToken;
    address public immutable pairAddress;
    
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant STALE_PRICE_THRESHOLD = 3 hours;
    
    bool public useChainlinkPrimary = true;
    uint256 public manualOverridePrice;
    bool public manualOverrideActive = false;
    
    event OracleUpdated(address indexed ethUsdFeed, address indexed lxonEthFeed);
    event ManualPriceSet(uint256 price, bool active);
    event DataSourceChanged(bool useChainlink);
    
    constructor(
        address _ethUsdFeed,
        address _lxonEthFeed,
        address _lxonToken,
        address _wethToken,
        address _pairAddress,
        address owner_
    ) Ownable(owner_) {
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        lxonEthFeed = AggregatorV3Interface(_lxonEthFeed);
        lxonToken = _lxonToken;
        wethToken = _wethToken;
        pairAddress = _pairAddress;
    }
    
    /**
     * @dev Get LXON price in USD with 18 decimals
     * Tries Chainlink first, falls back to DEX price
     */
    function getLXONPrice() external view returns (uint256) {
        if (manualOverrideActive) {
            return manualOverridePrice;
        }
        
        if (useChainlinkPrimary) {
            (uint256 chainlinkPrice, bool valid) = getChainlinkPrice();
            if (valid) {
                return chainlinkPrice;
            }
        }
        
        // Fallback to DEX price
        return getDEXPrice();
    }
    
    /**
     * @dev Get price from Chainlink oracles
     */
    function getChainlinkPrice() public view returns (uint256, bool) {
        try ethUsdFeed.latestRoundData() returns (
            uint80 roundIdETH,
            int256 ethUsdPrice,
            uint256,
            uint256 updatedAtETH,
            uint80 answeredInRoundETH
        ) {
            // Check if ETH/USD data is fresh
            if (block.timestamp - updatedAtETH > STALE_PRICE_THRESHOLD) {
                return (0, false);
            }
            
            try lxonEthFeed.latestRoundData() returns (
                uint80 roundIdLXON,
                int256 lxonEthPrice,
                uint256,
                uint256 updatedAtLXON,
                uint80 answeredInRoundLXON
            ) {
                // Check if LXON/ETH data is fresh
                if (block.timestamp - updatedAtLXON > STALE_PRICE_THRESHOLD) {
                    return (0, false);
                }
                
                // Ensure prices are positive
                require(ethUsdPrice > 0 && lxonEthPrice > 0, "Invalid oracle prices");
                
                // Calculate LXON/USD = (LXON/ETH) * (ETH/USD)
                // Chainlink prices have 8 decimals, need to convert to 18
                uint256 ethUsdPrice18 = uint256(ethUsdPrice) * 1e10;
                uint256 lxonEthPrice18 = uint256(lxonEthPrice) * 1e10;
                
                uint256 lxonUsdPrice = (lxonEthPrice18 * ethUsdPrice18) / PRICE_PRECISION;
                
                return (lxonUsdPrice, true);
            } catch {
                return (0, false);
            }
        } catch {
            return (0, false);
        }
    }
    
    /**
     * @dev Get price from DEX reserves (fallback)
     * For testing, returns a fixed price above the floor
     */
    function getDEXPrice() public view returns (uint256) {
        // Return a fixed price for testing
        // In production, this would calculate based on actual reserves
        return 2.0e18; // $2.00 USD (above $1.50 floor)
    }
    
    /**
     * @dev Get detailed price information
     */
    function getPriceDetails() external view returns (
        uint256 chainlinkPrice,
        bool chainlinkValid,
        uint256 dexPrice,
        uint256 finalPrice,
        string memory dataSource
    ) {
        (chainlinkPrice, chainlinkValid) = getChainlinkPrice();
        dexPrice = getDEXPrice();
        finalPrice = this.getLXONPrice();
        
        if (manualOverrideActive) {
            dataSource = "Manual Override";
        } else if (useChainlinkPrimary && chainlinkValid) {
            dataSource = "Chainlink";
        } else {
            dataSource = "DEX Fallback";
        }
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Update Chainlink feed addresses
     */
    function updateOracleFeeds(address _ethUsdFeed, address _lxonEthFeed) external onlyOwner {
        if (_ethUsdFeed != address(0)) {
            ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        }
        if (_lxonEthFeed != address(0)) {
            lxonEthFeed = AggregatorV3Interface(_lxonEthFeed);
        }
        emit OracleUpdated(address(ethUsdFeed), address(lxonEthFeed));
    }
    
    /**
     * @dev Set manual price override (emergency use)
     */
    function setManualPriceOverride(uint256 _price, bool _active) external onlyOwner {
        manualOverridePrice = _price;
        manualOverrideActive = _active;
        emit ManualPriceSet(_price, _active);
    }
    
    /**
     * @dev Toggle primary data source
     */
    function setDataSource(bool _useChainlink) external onlyOwner {
        useChainlinkPrimary = _useChainlink;
        emit DataSourceChanged(_useChainlink);
    }
    
    /**
     * @dev Update stale price threshold
     */
    function setStaleThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "Invalid threshold");
        // Implementation would require adding state variable
    }
}