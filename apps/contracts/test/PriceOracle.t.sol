// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}
}

contract PriceOracleTest is Test {
    PriceOracle oracle;
    MockToken token;
    
    address owner = address(0x1);
    address user = address(0x2);
    
    function setUp() public {
        vm.startPrank(owner);
        oracle = new PriceOracle();
        token = new MockToken();
        vm.stopPrank();
    }
    
    function testSetPriceFeed() public {
        vm.startPrank(owner);
        oracle.setPriceFeed(address(token), address(0x123));
        assertEq(oracle.priceFeeds(address(token)), address(0x123));
        vm.stopPrank();
    }
    
    function testUpdatePrice() public {
        vm.startPrank(owner);
        oracle.updatePrice(address(token), 1e18, 18);
        (uint256 price, uint256 timestamp, bool isStale) = oracle.getPrice(address(token));
        assertEq(price, 1e18);
        assertEq(timestamp, block.timestamp);
        assertEq(isStale, false);
        vm.stopPrank();
    }
    
    function testGetPriceInUSD() public {
        vm.startPrank(owner);
        oracle.updatePrice(address(token), 1e18, 18);
        uint256 usdValue = oracle.getPriceInUSD(address(token), 100 ether);
        assertEq(usdValue, 100 ether);
        vm.stopPrank();
    }
    
    function testIsPriceFresh() public {
        vm.startPrank(owner);
        oracle.updatePrice(address(token), 1e18, 18);
        assertTrue(oracle.isPriceFresh(address(token)));
        vm.stopPrank();
    }
    
    function testBatchUpdatePrices() public {
        vm.startPrank(owner);
        MockToken token2 = new MockToken();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);
        
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        
        oracle.batchUpdatePrices(tokens, prices, decimals);
        
        (uint256 price1, , ) = oracle.getPrice(address(token));
        (uint256 price2, , ) = oracle.getPrice(address(token2));
        
        assertEq(price1, 1e18);
        assertEq(price2, 2e18);
        vm.stopPrank();
    }
    
    function testPauseOracle() public {
        vm.startPrank(owner);
        oracle.pauseOracle();
        vm.expectRevert();
        oracle.updatePrice(address(token), 1e18, 18);
        vm.stopPrank();
    }
    
    function testUnpauseOracle() public {
        vm.startPrank(owner);
        oracle.pauseOracle();
        oracle.unpauseOracle();
        oracle.updatePrice(address(token), 1e18, 18);
        vm.stopPrank();
    }
    
    function testGetPriceStale() public {
        vm.startPrank(owner);
        oracle.updatePrice(address(token), 1e18, 18);
        
        // Warp time past staleness threshold
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert("Price is stale");
        oracle.getPrice(address(token));
        vm.stopPrank();
    }
}
