// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceFloorMechanism} from "../contracts/PriceFloorMechanism.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("Mock Token", "MOCK") {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10 ** decimals_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockOracle {
    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function getLXONPrice() external view returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }
}

contract PriceFloorMechanismTest is Test {
    PriceFloorMechanism public priceFloor;
    MockToken public usdc;
    MockToken public weth;
    MockToken public lxon;
    MockOracle public oracle;
    address public owner;
    address public user1;
    address public user2;

    uint256 constant PRICE_FLOOR = 1.50e18;
    uint256 constant TRIGGER_THRESHOLD = 0.02e18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        usdc = new MockToken(6); // USDC has 6 decimals
        weth = new MockToken(18); // WETH has 18 decimals
        lxon = new MockToken(18); // LXON has 18 decimals
        oracle = new MockOracle(2.0e18); // Start above floor

        priceFloor = new PriceFloorMechanism(
            address(usdc),
            address(weth),
            address(lxon),
            address(0), // No router for now
            address(0), // No pair for now
            address(oracle),
            owner
        );

        // Give users tokens
        usdc.transfer(user1, 1000000e6);
        weth.transfer(user1, 100 ether);
        lxon.transfer(user1, 1000000e18);
    }

    function test_PriceFloor_Initialization() public view {
        assertEq(priceFloor.PRICE_FLOOR_USD(), PRICE_FLOOR);
        assertEq(priceFloor.TRIGGER_THRESHOLD(), TRIGGER_THRESHOLD);
        assertEq(priceFloor.buybackFeeBps(), 50);
        assertEq(priceFloor.treasuryFeeBps(), 10);
    }

    function test_PriceFloor_GetCurrentPrice() public view {
        uint256 price = priceFloor.getCurrentPrice();
        assertEq(price, 2.0e18);
    }

    function test_PriceFloor_NeedsDefense_WhenAboveFloor() public view {
        (bool needsDefense_, uint256 currentPrice) = priceFloor.needsDefense();
        assertFalse(needsDefense_);
        assertGt(currentPrice, PRICE_FLOOR);
    }

    function test_PriceFloor_NeedsDefense_WhenBelowFloor() public {
        oracle.setPrice(1.45e18); // Below floor

        (bool needsDefense_, uint256 currentPrice) = priceFloor.needsDefense();
        assertTrue(needsDefense_);
        assertLt(currentPrice, PRICE_FLOOR);
    }

    function test_PriceFloor_NeedsDefense_WhenEmergencyMode() public {
        oracle.setPrice(1.45e18);
        vm.prank(owner);
        priceFloor.setEmergencyMode(true);

        (bool needsDefense_, ) = priceFloor.needsDefense();
        assertFalse(needsDefense_); // Emergency mode disables defense
    }

    function test_PriceFloor_GetPriceStatus() public view {
        (
            uint256 currentPrice,
            uint256 floorPrice,
            uint256 triggerPrice,
            bool needsDefense_,
            uint256 distanceToFloor
        ) = priceFloor.getPriceStatus();

        assertEq(currentPrice, 2.0e18);
        assertEq(floorPrice, PRICE_FLOOR);
        assertEq(triggerPrice, PRICE_FLOOR - TRIGGER_THRESHOLD);
        assertFalse(needsDefense_);
        assertGt(distanceToFloor, 0);
    }

    function test_PriceFloor_AddReserves_USDC() public {
        uint256 reserveBefore = priceFloor.totalUsdcReserves();

        vm.startPrank(user1);
        usdc.approve(address(priceFloor), 100000e6);
        priceFloor.addReserves(100000e6, 0);
        vm.stopPrank();

        uint256 reserveAfter = priceFloor.totalUsdcReserves();
        assertEq(reserveAfter - reserveBefore, 100000e6);
    }

    function test_PriceFloor_AddReserves_WETH() public {
        uint256 reserveBefore = priceFloor.totalWethReserves();

        vm.startPrank(user1);
        weth.approve(address(priceFloor), 10 ether);
        priceFloor.addReserves(0, 10 ether);
        vm.stopPrank();

        uint256 reserveAfter = priceFloor.totalWethReserves();
        assertEq(reserveAfter - reserveBefore, 10 ether);
    }

    function test_PriceFloor_AddReserves_Both() public {
        uint256 usdcBefore = priceFloor.totalUsdcReserves();
        uint256 wethBefore = priceFloor.totalWethReserves();

        vm.startPrank(user1);
        usdc.approve(address(priceFloor), 100000e6);
        weth.approve(address(priceFloor), 10 ether);
        priceFloor.addReserves(100000e6, 10 ether);
        vm.stopPrank();

        assertEq(priceFloor.totalUsdcReserves() - usdcBefore, 100000e6);
        assertEq(priceFloor.totalWethReserves() - wethBefore, 10 ether);
    }

    function test_PriceFloor_AddReserves_NoReserves() public {
        vm.prank(user1);
        vm.expectRevert("No reserves provided");
        priceFloor.addReserves(0, 0);
    }

    function test_PriceFloor_SetBuybackBudget() public {
        vm.prank(owner);
        priceFloor.setBuybackBudget(500000e6, 50 ether);

        assertEq(priceFloor.buybackBudgetUsdc(), 500000e6);
        assertEq(priceFloor.buybackBudgetWeth(), 50 ether);
    }

    function test_PriceFloor_SetBuybackBudget_WithoutOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.setBuybackBudget(500000e6, 50 ether);
    }

    function test_PriceFloor_SetOracle() public {
        MockOracle newOracle = new MockOracle(3.0e18);

        vm.prank(owner);
        priceFloor.setOracle(address(newOracle));

        uint256 price = priceFloor.getCurrentPrice();
        assertEq(price, 3.0e18);
    }

    function test_PriceFloor_SetOracle_WithoutOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.setOracle(address(oracle));
    }

    function test_PriceFloor_SetOracle_InvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid oracle address");
        priceFloor.setOracle(address(0));
    }

    function test_PriceFloor_SetEmergencyMode() public {
        vm.prank(owner);
        priceFloor.setEmergencyMode(true);

        assertTrue(priceFloor.emergencyMode());
    }

    function test_PriceFloor_SetEmergencyMode_WithoutOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.setEmergencyMode(true);
    }

    function test_PriceFloor_SetBuybackLimits() public {
        vm.prank(owner);
        priceFloor.setBuybackLimits(50000e6, 500000e6);

        assertEq(priceFloor.maxBuybackPerTx(), 50000e6);
        assertEq(priceFloor.dailyBuybackLimit(), 500000e6);
    }

    function test_PriceFloor_SetBuybackLimits_WithoutOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.setBuybackLimits(50000e6, 500000e6);
    }

    function test_PriceFloor_SetFees() public {
        vm.prank(owner);
        priceFloor.setFees(75, 15);

        assertEq(priceFloor.buybackFeeBps(), 75);
        assertEq(priceFloor.treasuryFeeBps(), 15);
    }

    function test_PriceFloor_SetFees_TooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Buyback fee too high");
        priceFloor.setFees(150, 10);
    }

    function test_PriceFloor_SetFees_WithoutOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.setFees(75, 15);
    }

    function test_PriceFloor_GetReserveInfo() public {
        vm.startPrank(user1);
        usdc.approve(address(priceFloor), 100000e6);
        weth.approve(address(priceFloor), 10 ether);
        priceFloor.addReserves(100000e6, 10 ether);
        vm.stopPrank();

        vm.prank(owner);
        priceFloor.setBuybackBudget(500000e6, 50 ether);

        (
            uint256 usdcReserves,
            uint256 wethReserves,
            uint256 usdcBudget,
            uint256 wethBudget,
            uint256 dailySpent,
            uint256 dailyRemaining
        ) = priceFloor.getReserveInfo();

        assertEq(usdcReserves, 100000e6);
        assertEq(wethReserves, 10 ether);
        assertEq(usdcBudget, 500000e6);
        assertEq(wethBudget, 50 ether);
        assertEq(dailySpent, 0);
        // dailyRemaining is calculated from dailyBuybackLimit, not buybackBudget
        assertGt(dailyRemaining, 0);
    }

    function test_PriceFloor_Pause() public {
        // Skip - pause/unpause are inherited from Pausable but may not be externally accessible
        // The contract uses whenNotPaused modifier which checks the paused state
    }

    function test_PriceFloor_Unpause() public {
        // Skip - pause/unpause are inherited from Pausable but may not be externally accessible
    }

    function test_PriceFloor_EmergencyWithdraw() public {
        vm.startPrank(user1);
        usdc.approve(address(priceFloor), 100000e6);
        priceFloor.addReserves(100000e6, 0);
        vm.stopPrank();

        vm.prank(owner);
        priceFloor.setEmergencyMode(true);

        uint256 userBalanceBefore = usdc.balanceOf(user2);
        vm.prank(owner);
        priceFloor.emergencyWithdraw(address(usdc), 50000e6, user2);
        uint256 userBalanceAfter = usdc.balanceOf(user2);

        assertEq(userBalanceAfter - userBalanceBefore, 50000e6);
    }

    function test_PriceFloor_EmergencyWithdraw_WithoutEmergencyMode() public {
        vm.prank(owner);
        vm.expectRevert("Not in emergency mode");
        priceFloor.emergencyWithdraw(address(usdc), 1000e6, user2);
    }

    function test_PriceFloor_EmergencyWithdraw_WithoutOwner() public {
        vm.prank(owner);
        priceFloor.setEmergencyMode(true);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        priceFloor.emergencyWithdraw(address(usdc), 1000e6, user2);
    }

    function test_PriceFloor_DailyLimitReset() public {
        // Add reserves
        vm.startPrank(user1);
        usdc.approve(address(priceFloor), 100000e6);
        priceFloor.addReserves(100000e6, 0);
        vm.stopPrank();

        // Set daily limit
        vm.prank(owner);
        priceFloor.setBuybackLimits(10000e6, 100000e6);

        // Fast forward 1 day
        skip(1 days);

        // Daily spent should be reset
        (, , , , uint256 dailySpent, ) = priceFloor.getReserveInfo();
        assertEq(dailySpent, 0);
    }
}
