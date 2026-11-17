// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {USDL} from "../../src/USDL.sol";
import {MockERC20} from "./MockERC20.sol";

contract USDCTest is Test {
    MockERC20 usdc;
    MockERC20 lxon;
    USDL usdl;

    function setUp() public {
        usdc = new MockERC20();
        lxon = new MockERC20();
        usdl = new USDL(address(usdc), address(lxon), address(0xdead));
        usdc.mint(address(this), 1_000_000 ether);
        lxon.mint(address(this), 1_000_000 ether);
        usdc.approve(address(usdl), type(uint256).max);
        lxon.approve(address(usdl), type(uint256).max);
    }

    function test_mint_and_burn() public {
        usdl.mint(100 ether);
        assertEq(usdl.balanceOf(address(this)), 100 ether);
        assertEq(usdl.totalSupply(), 100 ether);

        usdl.burn(50 ether);
        assertEq(usdl.balanceOf(address(this)), 50 ether);
    }

    function test_reserve_ratio_zero_when_empty() public view {
        assertEq(usdl.getReserveRatio(), 0);
    }
}