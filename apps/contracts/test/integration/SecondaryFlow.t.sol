// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {SecondarySignature} from "../../contracts/crypto/SecondarySignature.sol";
import {PQWrappedAssetVault} from "../../contracts/wrapper/PQWrappedAssetVault.sol";
import {ValidatorKeyRegistry} from "../../contracts/governance/ValidatorKeyRegistry.sol";
import {MockCustodianAdapter} from "../mocks/MockCustodianAdapter.sol";
import {MockWrappedAsset} from "../mocks/MockWrappedAsset.sol";

/**
 * End-to-end test: validator registration → large deposit → secondary
 * attestation → withdrawal.
 */
contract SecondaryFlowIntegrationTest is Test {
    SecondarySignature secondary;
    PQWrappedAssetVault vault;
    ValidatorKeyRegistry registry;
    MockCustodianAdapter custodian;
    MockWrappedAsset wrappedAsset;
    address gov = address(0xA11CE);
    address att = address(0xA77E);
    address relayer = address(0x1234);
    address validator = address(0x5678);

    function setUp() public {
        vm.startPrank(gov);
        secondary = new SecondarySignature(gov);
        secondary.setAttestor(att, true);

        custodian = new MockCustodianAdapter();
        wrappedAsset = new MockWrappedAsset();
        vault = new PQWrappedAssetVault(address(secondary));
        vault.setRelayer(relayer, true);
        vault.setThresholds(1000 ether, 100_000 ether, 2);

        registry = new ValidatorKeyRegistry(gov);
        registry.setSecondaryScheme(1, true);
        vm.stopPrank();
    }

    function test_full_flow_large_deposit() public {
        // 1. Register wrapped asset
        bytes32 assetId = keccak256("BTC");
        vm.prank(gov);
        vault.registerWrappedAsset(assetId, address(wrappedAsset));

        // 2. Register secondary attestation
        bytes32 commitment = keccak256("honey-commitment");
        vm.prank(att);
        secondary.attest(commitment, SecondarySignature.Scheme.MAYO_1);

        // 3. Submit large deposit (requires secondary)
        bytes32 ref = keccak256("dep-1");
        vm.prank(relayer);
        vault.submitAttestation(
            ref, assetId, address(custodian),
            address(0xB0B), 5000 ether,
            keccak256("primary"), commitment, ""
        );

        // 4. Verify processed
        (,,,,,,,, bool processed,) = vault.attestations(ref);
        assertTrue(processed);
    }

    function test_validator_registers_both_keys() public {
        bytes32 pk = keccak256("mdsa");
        bytes32 sk = keccak256("mayo");
        vm.startPrank(validator);
        registry.proposeRotation(pk); registry.acceptRotation();
        registry.proposeSecondaryRotation(sk); registry.acceptSecondaryRotation();
        vm.stopPrank();

        assertTrue(registry.isAuthorized(validator, pk));
        assertTrue(registry.isSecondaryAuthorized(validator, sk));
    }
}
