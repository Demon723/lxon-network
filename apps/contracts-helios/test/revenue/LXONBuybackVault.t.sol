// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {LXONBuybackVault} from "../../src/revenue/LXONBuybackVault.sol";
import {MockERC20} from "../MockERC20.sol";

contract LXONBuybackVaultTest is Test {
    MockERC20 lxon;
    LXONBuybackVault vault;

    function setUp() public {
        lxon = new MockERC20();
        vault = new LXONBuybackVault(address(lxon));
        lxon.mint(address(this), 1000 ether);
        lxon.approve(address(vault), type(uint256).max);
    }

    function test_burn() public {
        vault.burn(100 ether);
        assertEq(lxon.balanceOf(0x000000000000000000000000000000000000dEaD), 100 ether);
        assertEq(vault.totalBurned(), 100 ether);
    }

    function test_zero_burn_reverts() public {
        vm.expectRevert(LXONBuybackVault.ZeroAmount.selector);
        vault.burn(0);
    }
}
