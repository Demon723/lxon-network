// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LXONBuybackBurn.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract LXONBuybackBurnFixedTest is Test {
    LXONBuybackBurn public buybackBurn;
    MockERC20 public lxonToken;
    MockERC20 public baseToken;
    
    address public owner;
    address public treasury;
    address public user;
    
    uint256 public constant INITIAL_BALANCE = 1_000_000 * 10**18;
    uint256 public constant MAX_SINGLE_BUYBACK = 100_000 * 10**18;

    function setUp() public {
        owner = address(this);
        treasury = address(0x1);
        user = address(0x2);
        
        lxonToken = new MockERC20();
        baseToken = new MockERC20();
        
        // Transfer tokens to treasury
        baseToken.transfer(treasury, INITIAL_BALANCE);
        lxonToken.transfer(treasury, INITIAL_BALANCE);
        
        // Deploy contract
        buybackBurn = new LXONBuybackBurn(
            address(lxonToken),
            address(baseToken),
            treasury,
            1 * 10**18, // buyback threshold
            10, // buyback percentage (10%)
            MAX_SINGLE_BUYBACK
        );
        
        // Enable buyback
        buybackBurn.toggleBuyback(true);
        
        // Mint additional tokens to owner for test use
        lxonToken.mint(owner, INITIAL_BALANCE);
        baseToken.mint(owner, INITIAL_BALANCE);
    }

    function testDeployment() public {
        assertEq(address(buybackBurn.lxonToken()), address(lxonToken));
        assertEq(address(buybackBurn.baseToken()), address(baseToken));
        assertEq(buybackBurn.treasury(), treasury);
        assertEq(buybackBurn.maxSingleBuyback(), MAX_SINGLE_BUYBACK);
        assertTrue(buybackBurn.buybackEnabled());
    }

    function testTreasuryDeposit() public {
        uint256 depositAmount = 50_000 * 10**18;
        
        vm.prank(treasury);
        baseToken.approve(address(buybackBurn), depositAmount);
        
        vm.prank(treasury);
        buybackBurn.treasuryDeposit(depositAmount);
        
        assertEq(baseToken.balanceOf(address(buybackBurn)), depositAmount);
        assertEq(baseToken.balanceOf(treasury), INITIAL_BALANCE - depositAmount);
    }

    function testTreasuryDepositUnauthorized() public {
        uint256 depositAmount = 50_000 * 10**18;
        
        vm.prank(user);
        vm.expectRevert("Only treasury can deposit");
        buybackBurn.treasuryDeposit(depositAmount);
    }

    function testTreasuryDepositZeroAmount() public {
        vm.prank(treasury);
        vm.expectRevert("Amount must be greater than 0");
        buybackBurn.treasuryDeposit(0);
    }

    function testExecuteBuybackWithDepositedFunds() public {
        uint256 depositAmount = 50_000 * 10**18;
        uint256 buybackAmount = 10_000 * 10**18;
        
        // Treasury deposits funds
        vm.prank(treasury);
        baseToken.approve(address(buybackBurn), depositAmount);
        vm.prank(treasury);
        buybackBurn.treasuryDeposit(depositAmount);
        
        // Mint LXON tokens to contract for burning
        lxonToken.mint(address(buybackBurn), 5_000 * 10**18);
        
        // Execute buyback
        buybackBurn.executeBuyback(buybackAmount, 1);
        
        // Verify buyback executed
        (uint256 totalBuyback, uint256 totalBurned, uint256 threshold, uint256 percentage, bool enabled, uint256 treasuryBal, uint256 contractLXON) = buybackBurn.getStats();
        assertEq(totalBuyback, buybackAmount);
        assertEq(totalBurned, 5_000 * 10**18);
        assertEq(lxonToken.balanceOf(0x000000000000000000000000000000000000dEaD), 5_000 * 10**18);
    }

    function testExecuteBuybackExceedsMaxSingleBuyback() public {
        uint256 depositAmount = 200_000 * 10**18;
        uint256 buybackAmount = 150_000 * 10**18; // Exceeds MAX_SINGLE_BUYBACK
        
        vm.prank(treasury);
        baseToken.approve(address(buybackBurn), depositAmount);
        vm.prank(treasury);
        buybackBurn.treasuryDeposit(depositAmount);
        
        lxonToken.mint(address(buybackBurn), 50_000 * 10**18);
        
        vm.expectRevert("Amount exceeds maximum single buyback");
        buybackBurn.executeBuyback(buybackAmount, 1);
    }

    function testExecuteBuybackInsufficientContractBalance() public {
        uint256 buybackAmount = 10_000 * 10**18;
        
        // No funds deposited
        lxonToken.mint(address(buybackBurn), 5_000 * 10**18);
        
        vm.expectRevert("Insufficient contract balance");
        buybackBurn.executeBuyback(buybackAmount, 1);
    }

    function testExecuteBuybackBuybackDisabled() public {
        buybackBurn.toggleBuyback(false);
        
        uint256 depositAmount = 50_000 * 10**18;
        uint256 buybackAmount = 10_000 * 10**18;
        
        vm.prank(treasury);
        baseToken.approve(address(buybackBurn), depositAmount);
        vm.prank(treasury);
        buybackBurn.treasuryDeposit(depositAmount);
        
        lxonToken.mint(address(buybackBurn), 5_000 * 10**18);
        
        vm.expectRevert("Buyback is disabled");
        buybackBurn.executeBuyback(buybackAmount, 1);
    }

    function testSetMaxSingleBuyback() public {
        uint256 newMax = 200_000 * 10**18;
        
        buybackBurn.setMaxSingleBuyback(newMax);
        
        assertEq(buybackBurn.maxSingleBuyback(), newMax);
    }

    function testSetMaxSingleBuybackUnauthorized() public {
        uint256 newMax = 200_000 * 10**18;
        
        vm.prank(user);
        vm.expectRevert();
        buybackBurn.setMaxSingleBuyback(newMax);
    }

    function testSetMaxSingleBuybackZero() public {
        vm.expectRevert("Max must be greater than 0");
        buybackBurn.setMaxSingleBuyback(0);
    }

    function testManualBurn() public {
        uint256 burnAmount = 1_000 * 10**18;
        
        lxonToken.mint(address(buybackBurn), burnAmount);
        
        buybackBurn.manualBurn(burnAmount);
        
        (uint256 totalBuyback, uint256 totalBurned, uint256 threshold, uint256 percentage, bool enabled, uint256 treasuryBal, uint256 contractLXON) = buybackBurn.getStats();
        assertEq(totalBurned, burnAmount);
        assertEq(lxonToken.balanceOf(address(buybackBurn)), 0);
        assertEq(lxonToken.balanceOf(0x000000000000000000000000000000000000dEaD), burnAmount);
    }

    function testManualBurnUnauthorized() public {
        uint256 burnAmount = 1_000 * 10**18;
        
        lxonToken.mint(address(buybackBurn), burnAmount);
        
        vm.prank(user);
        vm.expectRevert();
        buybackBurn.manualBurn(burnAmount);
    }

    function testWithdrawBaseToken() public {
        uint256 withdrawAmount = 10_000 * 10**18;
        
        baseToken.mint(address(buybackBurn), withdrawAmount);
        
        buybackBurn.withdrawBaseToken(withdrawAmount, user);
        
        assertEq(baseToken.balanceOf(user), withdrawAmount);
    }

    function testWithdrawBaseTokenUnauthorized() public {
        uint256 withdrawAmount = 10_000 * 10**18;
        
        baseToken.mint(address(buybackBurn), withdrawAmount);
        
        vm.prank(user);
        vm.expectRevert();
        buybackBurn.withdrawBaseToken(withdrawAmount, user);
    }

    function testWithdrawBaseTokenInvalidRecipient() public {
        uint256 withdrawAmount = 10_000 * 10**18;
        
        baseToken.mint(address(buybackBurn), withdrawAmount);
        
        vm.expectRevert("Invalid recipient");
        buybackBurn.withdrawBaseToken(withdrawAmount, address(0));
    }

    function testGetStats() public {
        (uint256 totalBuyback, uint256 totalBurned, uint256 threshold, uint256 percentage, bool enabled, uint256 treasuryBal, uint256 contractLXON) = buybackBurn.getStats();
        
        assertEq(totalBuyback, 0);
        assertEq(totalBurned, 0);
        assertEq(threshold, 1 * 10**18);
        assertEq(percentage, 10);
        assertTrue(enabled);
        assertEq(treasuryBal, INITIAL_BALANCE);
        assertEq(contractLXON, 0);
    }
}
