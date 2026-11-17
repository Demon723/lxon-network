// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {PQWrappedAsset} from "../../src/wrapper/PQWrappedAsset.sol";
import {MockERC20} from "../MockERC20.sol";

contract PQWrappedAssetTest is Test {
    PQWrappedAsset qbtc;
    MockERC20 usdc;
    address custodian = address(0xC0570D);
    address alice = address(0xA11CE);

    function setUp() public {
        usdc = new MockERC20();
        qbtc = new PQWrappedAsset(
            "Quantum BTC", "qBTC",
            PQWrappedAsset.AssetClass.Native,
            address(0), 8
        );
        qbtc.setCustodian(custodian, true);
        qbtc.setThreshold(1);
    }

    function test_attest_native() public {
        vm.prank(custodian);
        qbtc.attestNative(alice, 100_000_000, keccak256("ref-1"));
        assertEq(qbtc.balanceOf(alice), 100_000_000);
        assertEq(qbtc.totalMinted(), 100_000_000);
        assertEq(qbtc.circulating(), 100_000_000);
    }

    function test_only_custodian_can_attest() public {
        vm.prank(alice);
        vm.expectRevert(PQWrappedAsset.NotCustodian.selector);
        qbtc.attestNative(alice, 1, keccak256("x"));
    }

    function test_redemption_closed_by_default() public {
        vm.prank(custodian);
        qbtc.attestNative(alice, 100, keccak256("r"));
        vm.prank(alice);
        vm.expectRevert(PQWrappedAsset.RedemptionClosed.selector);
        qbtc.unwrap(100, keccak256("u"));
    }

    function test_open_redemption_and_unwrap() public {
        vm.prank(custodian);
        qbtc.attestNative(alice, 100, keccak256("r"));

        qbtc.openRedemption();
        vm.prank(alice);
        qbtc.unwrap(40, keccak256("u"));

        assertEq(qbtc.balanceOf(alice), 60);
        assertEq(qbtc.totalRedeemed(), 40);
        assertEq(qbtc.circulating(), 60);
    }

    function test_custodian_nonce_increments() public {
        vm.startPrank(custodian);
        qbtc.attestNative(alice, 1, keccak256("1"));
        qbtc.attestNative(alice, 1, keccak256("2"));
        vm.stopPrank();
        assertEq(qbtc.custodianNonce(custodian), 2);
    }
}
