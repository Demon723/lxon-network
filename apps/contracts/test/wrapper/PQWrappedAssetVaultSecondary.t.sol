// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {PQWrappedAssetVault} from "../../contracts/wrapper/PQWrappedAssetVault.sol";
import {SecondarySignature} from "../../contracts/crypto/SecondarySignature.sol";
import {MockCustodianAdapter} from "../mocks/MockCustodianAdapter.sol";

contract PQWrappedAssetVaultSecondaryTest is Test {
    PQWrappedAssetVault vault;
    SecondarySignature secondary;
    MockCustodianAdapter custodian;
    address gov = address(0xA11CE);
    address att = address(0xA77E);
    address relayer = address(0x1234);

    function setUp() public {
        vm.startPrank(gov);
        secondary = new SecondarySignature(gov);
        secondary.setAttestor(att, true);
        custodian = new MockCustodianAdapter();
        vault = new PQWrappedAssetVault(address(secondary));
        vault.setRelayer(relayer, true);
        vault.setThresholds(1000 ether, 100_000 ether, 2);
        vm.stopPrank();
    }

    function test_thresholds_set() public view {
        assertEq(vault.largeThreshold(), 1000 ether);
        assertEq(vault.hugeThreshold(), 100_000 ether);
    }

    function test_secondary_required_above_threshold() public {
        bytes32 ref = keccak256("dep-1");
        bytes32 assetId = keccak256("BTC");
        address wrappedAsset = address(0xBEEF);
        
        // Register wrapped asset
        vm.prank(gov);
        vault.registerWrappedAsset(assetId, wrappedAsset);
        
        // Large amount, no secondary commitment — should revert
        vm.prank(relayer);
        vm.expectRevert(PQWrappedAssetVault.SecondaryRequired.selector);
        vault.submitAttestation(
            ref, assetId, address(custodian),
            address(0xB0B), 5000 ether,
            keccak256("primary"), bytes32(0), ""
        );
    }
}
