// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILXON {
    function mint(address to, uint256 usdCents, bytes32 depositRef) external;
    function redeem(uint256 amount, bytes32 wireRef) external;
    function balanceOf(address) external view returns (uint256);
}

interface IPriceOracle {
    function getLXONPrice() external view returns (uint256 priceInUSD);
}

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IPair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

/**
 * @title PriceFloorMechanism
 * @dev Maintains a minimum price floor of $1.50 for LXON token
 * Uses treasury reserves to buy back LXON when price drops below floor
 */
contract PriceFloorMechanism is Pausable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IERC20 public immutable weth;
    address public immutable lxonToken;
    IRouter public immutable router;
    IPair public immutable pair;
    IPriceOracle public oracle;

    // Price floor configuration
    uint256 public constant PRICE_FLOOR_USD = 1.50e18; // $1.50 with 18 decimals
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant TRIGGER_THRESHOLD = 0.02e18; // 2% below floor triggers buyback
    
    // Treasury management
    uint256 public totalUsdcReserves;
    uint256 public totalWethReserves;
    uint256 public buybackBudgetUsdc;
    uint256 public buybackBudgetWeth;
    
    // Fee configuration (in basis points)
    uint256 public buybackFeeBps = 50; // 0.5% fee on buybacks
    uint256 public treasuryFeeBps = 10; // 0.1% fee goes to treasury

    // Limits and controls
    uint256 public maxBuybackPerTx = 100000e6; // Max 100k USDC per transaction
    uint256 public dailyBuybackLimit = 1000000e6; // Max 1M USDC per day
    uint256 public dailyBuybackSpent;
    uint256 public lastResetTime;

    // Emergency controls
    bool public emergencyMode = false;
    uint256 public emergencyCooldown = 1 hours;

    event PriceFloorDefended(uint256 price, uint256 amountBought, uint256 reserveUsed);
    event BuybackTriggered(uint256 currentPrice, uint256 floorPrice);
    event ReservesAdded(address indexed provider, uint256 usdcAmount, uint256 wethAmount);
    event BudgetUpdated(uint256 usdcBudget, uint256 wethBudget);
    event EmergencyModeToggled(bool enabled);
    event OracleUpdated(address indexed newOracle);

    constructor(
        address _usdc,
        address _weth,
        address _lxon,
        address _router,
        address _pair,
        address _oracle,
        address owner_
    ) Ownable(owner_) {
        usdc = IERC20(_usdc);
        weth = IERC20(_weth);
        lxonToken = _lxon;
        router = IRouter(_router);
        pair = IPair(_pair);
        oracle = IPriceOracle(_oracle);
        
        lastResetTime = block.timestamp;
    }

    // ========== PRICE MONITORING ==========

    /**
     * @dev Get current LXON price from oracle
     */
    function getCurrentPrice() public view returns (uint256) {
        return oracle.getLXONPrice();
    }

    /**
     * @dev Check if price floor defense is needed
     */
    function needsDefense() public view returns (bool, uint256) {
        uint256 currentPrice = getCurrentPrice();
        uint256 triggerPrice = PRICE_FLOOR_USD - TRIGGER_THRESHOLD;
        
        if (currentPrice < triggerPrice && !emergencyMode) {
            return (true, currentPrice);
        }
        return (false, currentPrice);
    }

    // ========== BUYBACK MECHANISM ==========

    /**
     * @dev Execute buyback when price drops below floor
     */
    function defendPriceFloor() external whenNotPaused nonReentrant {
        (bool needsDefense_, uint256 currentPrice) = needsDefense();
        require(needsDefense_, "Price floor not breached");
        require(!emergencyMode, "Emergency mode active");

        _resetDailyLimitIfNeeded();
        
        emit BuybackTriggered(currentPrice, PRICE_FLOOR_USD);

        // Calculate optimal buyback amount
        uint256 buybackAmount = _calculateBuybackAmount(currentPrice);
        require(buybackAmount > 0, "Insufficient buyback calculated");
        require(buybackAmount <= maxBuybackPerTx, "Exceeds max per-tx limit");
        require(buybackAmount <= dailyBuybackLimit - dailyBuybackSpent, "Exceeds daily limit");

        // Execute buyback with USDC (primary) or WETH (fallback)
        bool success = _executeBuyback(buybackAmount);
        require(success, "Buyback execution failed");

        emit PriceFloorDefended(currentPrice, buybackAmount, buybackAmount);
    }

    /**
     * @dev Calculate optimal buyback amount based on price deviation
     */
    function _calculateBuybackAmount(uint256 currentPrice) internal view returns (uint256) {
        uint256 priceGap = PRICE_FLOOR_USD - currentPrice;
        uint256 gapPercentage = (priceGap * PRICE_PRECISION) / PRICE_FLOOR_USD;
        
        // Scale buyback aggressiveness with price gap
        // Small gap (<1%): Conservative buyback
        // Medium gap (1-3%): Moderate buyback  
        // Large gap (>3%): Aggressive buyback
        
        uint256 baseAmount = 10000e6; // Base 10k USDC
        uint256 multiplier = 1e18;
        
        if (gapPercentage < 0.01e18) {
            multiplier = 1e18; // 1x
        } else if (gapPercentage < 0.03e18) {
            multiplier = 2e18; // 2x
        } else {
            multiplier = 5e18; // 5x
        }
        
        uint256 calculatedAmount = (baseAmount * multiplier) / PRICE_PRECISION;
        
        // Respect available budget
        uint256 availableUsdc = usdc.balanceOf(address(this));
        return calculatedAmount < availableUsdc ? calculatedAmount : availableUsdc;
    }

    /**
     * @dev Execute the actual buyback transaction
     */
    function _executeBuyback(uint256 usdcAmount) internal returns (bool) {
        // Try USDC buyback first
        if (usdc.balanceOf(address(this)) >= usdcAmount) {
            return _buybackWithUSDC(usdcAmount);
        }
        
        // Fallback to WETH buyback
        uint256 wethAmount = _convertUSDCtoWETH(usdcAmount);
        if (weth.balanceOf(address(this)) >= wethAmount) {
            return _buybackWithWETH(wethAmount);
        }
        
        return false;
    }

    /**
     * @dev Buyback using USDC
     * Note: Currently simplified to directly use WETH for buyback
     * Full USDC support would require additional DEX infrastructure
     */
    function _buybackWithUSDC(uint256 usdcAmount) internal returns (bool) {
        // For now, fallback to WETH buyback
        // In production, would swap USDC -> WETH -> LXON
        uint256 wethAmount = _convertUSDCtoWETH(usdcAmount);
        return _buybackWithWETH(wethAmount);
    }

    /**
     * @dev Buyback using WETH
     * Direct WETH -> LXON swap using Router
     */
    function _buybackWithWETH(uint256 wethAmount) internal returns (bool) {
        uint256 fee = (wethAmount * buybackFeeBps) / 10000;
        uint256 netAmount = wethAmount - fee;

        dailyBuybackSpent += _convertWETHtoUSDC(wethAmount);

        // Approve and swap
        weth.forceApprove(address(router), wethAmount);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = lxonToken;

        try router.swapExactTokensForTokens(
            netAmount,
            0, // Accept any amount out
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            // Transfer purchased LXON to deployer/treasury (price defense)
            uint256 lxonBought = amounts[1];
            if (lxonBought > 0) {
                IERC20(lxonToken).safeTransfer(owner(), lxonBought);
            }
            return true;
        } catch {
            return false;
        }
    }

    function _convertWETHtoUSDC(uint256 wethAmount) internal view returns (uint256) {
        // Simple conversion - assuming 1 ETH = $2000
        return (wethAmount * 2000 * 1e6) / 1e18;
    }

    // ========== RESERVE MANAGEMENT ==========

    /**
     * @dev Add reserves to the price floor treasury
     */
    function addReserves(uint256 usdcAmount, uint256 wethAmount) external {
        require(usdcAmount > 0 || wethAmount > 0, "No reserves provided");

        if (usdcAmount > 0) {
            uint256 balanceBefore = usdc.balanceOf(address(this));
            usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
            uint256 balanceAfter = usdc.balanceOf(address(this));
            uint256 actualReceived = balanceAfter - balanceBefore;
            totalUsdcReserves += actualReceived;
        }

        if (wethAmount > 0) {
            uint256 balanceBefore = weth.balanceOf(address(this));
            weth.safeTransferFrom(msg.sender, address(this), wethAmount);
            uint256 balanceAfter = weth.balanceOf(address(this));
            uint256 actualReceived = balanceAfter - balanceBefore;
            totalWethReserves += actualReceived;
        }

        emit ReservesAdded(msg.sender, usdcAmount, wethAmount);
    }

    /**
     * @dev Set buyback budgets
     */
    function setBuybackBudget(uint256 usdcBudget, uint256 wethBudget) external onlyOwner {
        buybackBudgetUsdc = usdcBudget;
        buybackBudgetWeth = wethBudget;
        emit BudgetUpdated(usdcBudget, wethBudget);
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @dev Update price oracle
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle address");
        oracle = IPriceOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    /**
     * @dev Toggle emergency mode
     */
    function setEmergencyMode(bool _emergencyMode) external onlyOwner {
        emergencyMode = _emergencyMode;
        emit EmergencyModeToggled(_emergencyMode);
    }

    /**
     * @dev Update buyback limits
     */
    function setBuybackLimits(uint256 _maxPerTx, uint256 _dailyLimit) external onlyOwner {
        maxBuybackPerTx = _maxPerTx;
        dailyBuybackLimit = _dailyLimit;
    }

    /**
     * @dev Update fees
     */
    function setFees(uint256 _buybackFeeBps, uint256 _treasuryFeeBps) external onlyOwner {
        require(_buybackFeeBps <= 100, "Buyback fee too high");
        require(_treasuryFeeBps <= 100, "Treasury fee too high");
        buybackFeeBps = _buybackFeeBps;
        treasuryFeeBps = _treasuryFeeBps;
    }

    /**
     * @dev Emergency withdraw (emergency mode only)
     */
    function emergencyWithdraw(address token, uint256 amount, address to) external onlyOwner {
        require(emergencyMode, "Not in emergency mode");
        IERC20(token).safeTransfer(to, amount);
    }

    // ========== UTILITY FUNCTIONS ==========

    function _resetDailyLimitIfNeeded() internal {
        if (block.timestamp >= lastResetTime + 1 days) {
            dailyBuybackSpent = 0;
            lastResetTime = block.timestamp;
        }
    }

    function _convertUSDCtoWETH(uint256 usdcAmount) internal view returns (uint256) {
        // Simple conversion - in production, use oracle or DEX price
        // Assuming 1 ETH = $2000 for now
        return (usdcAmount * 1e18) / (2000 * 1e6);
    }

    // ========== VIEW FUNCTIONS ==========

    function getReserveInfo() external view returns (
        uint256 usdcReserves,
        uint256 wethReserves,
        uint256 usdcBudget,
        uint256 wethBudget,
        uint256 dailySpent,
        uint256 dailyRemaining
    ) {
        return (
            totalUsdcReserves,
            totalWethReserves,
            buybackBudgetUsdc,
            buybackBudgetWeth,
            dailyBuybackSpent,
            dailyBuybackLimit - dailyBuybackSpent
        );
    }

    function getPriceStatus() external view returns (
        uint256 currentPrice,
        uint256 floorPrice,
        uint256 triggerPrice,
        bool needsDefense_,
        uint256 distanceToFloor
    ) {
        currentPrice = getCurrentPrice();
        floorPrice = PRICE_FLOOR_USD;
        triggerPrice = PRICE_FLOOR_USD - TRIGGER_THRESHOLD;
        (needsDefense_,) = needsDefense();
        distanceToFloor = currentPrice >= floorPrice ? 
            currentPrice - floorPrice : floorPrice - currentPrice;
    }
}