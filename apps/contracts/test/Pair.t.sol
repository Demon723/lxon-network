// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../contracts/WETH.sol";
import {LXON} from "../contracts/LXON.sol";
import {Pair} from "../contracts/Pair.sol";
import {Router} from "../contracts/Router.sol";

contract PairTest is Test {
    WETH9 public weth;
    LXON public lxon;
    Pair public pair;
    Router public router;
    address public user1;
    address public user2;

    bytes32 constant MINT_ROLE = bytes32(uint256(keccak256("MINT_ROLE")));
    bytes32 constant ORACLE_ROLE = bytes32(uint256(keccak256("ORACLE_ROLE")));
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        weth = new WETH9();
        lxon = new LXON(address(this));
        pair = new Pair(address(weth), address(lxon));
        router = new Router(address(weth), address(lxon), address(pair));
        weth.deposit{value: 1000 ether}(user1);
        weth.deposit{value: 1000 ether}(user2);
        lxon.grantRole(DEFAULT_ADMIN_ROLE, address(this));
        lxon.grantRole(MINT_ROLE, address(this));
        lxon.grantRole(ORACLE_ROLE, address(this));
        lxon.updateCeiling(1000000000000, bytes32(0));
        lxon.mint(address(this), 1000000, bytes32(0));
    }

    function test_Pair_Initialization() public view {
        assertEq(pair.token0(), address(weth), "token0 should be WETH");
        assertEq(pair.token1(), address(lxon), "token1 should be LXON");
    }

    function test_Pair_GetReserves_AfterInit() public view {
        (uint256 r0, uint256 r1, ) = pair.getReserves();
        assertEq(r0, 0, "reserve0 should be 0");
        assertEq(r1, 0, "reserve1 should be 0");
    }

    function test_Pair_Mint_InitialLiquidity() public {
        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user1);

        (uint256 r0, uint256 r1, ) = pair.getReserves();
        assertEq(r0, 1000 ether, "reserve0 should be 1000 ether");
        assertEq(r1, 10000000000, "reserve1 should be 10000000000");
        assertGt(pair.totalSupply(), 0, "totalSupply should be > 0");
        assertGt(pair.balanceOf(user1), 0, "user1 should have LP tokens");
    }

    function test_Pair_Mint_SecondLiquidityProvider() public {
        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user1);

        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user2);

        assertGt(pair.balanceOf(user2), 0, "user2 should have LP tokens");
        assertGt(pair.totalSupply(), pair.balanceOf(user1), "totalSupply should increase");
    }

    function test_Pair_Swap() public {
        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user1);

        lxon.mint(address(this), 1000000, bytes32(0));
        lxon.approve(address(router), 1000000);
        uint256 amountWLXONBefore = weth.balanceOf(address(pair));
        router.swapLXONForWETH(1000000, 0, user2, block.timestamp + 1 days);
        uint256 amountWLXONAfter = weth.balanceOf(address(pair));
        assertGt(amountWLXONBefore, amountWLXONAfter, "WETH should decrease from pool");
    }

    function test_Pair_GetAmountOut() public {
        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user1);

        uint256 amountOut = pair.getAmountOut(100000, 10000000000, 10000000000);
        assertGt(amountOut, 0, "amountOut should be > 0");
    }

    function test_Pair_Burn() public {
        lxon.mint(address(pair), 1000000, bytes32(0));
        weth.deposit{value: 1000 ether}(address(pair));
        pair.mint(user1);

        assertGt(pair.balanceOf(user1), 0, "should have LP tokens");
        vm.prank(user1);
        pair.burn(user1);
        assertEq(pair.totalSupply(), 1, "totalSupply should be MINIMUM_LIQUIDITY after burn");
    }

    function test_Pair_IdenticalAddresses() public {
        vm.expectRevert("Pair: IDENTICAL_ADDRESSES");
        new Pair(address(weth), address(weth));
    }
}
