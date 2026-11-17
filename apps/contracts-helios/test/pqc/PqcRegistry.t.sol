// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";
import {PqcSchemeWord} from "../../src/pqc/PqcSchemeWord.sol";

contract PqcRegistryTest is Test {
    PqcAlgorithmRegistry reg;
    address constant ADMIN = address(0xA11CE); // named in the plan; the test contract holds the role
    address pauser = address(0x9A15E);  // stands in for the bridge pauser
    bytes32 constant MAYO2 = keccak256("mayo2");
    bytes32 constant MLDSA = keccak256("mldsa44");

    function setUp() public {
        // The test contract holds SCHEME_ADMIN_ROLE so the admin-path cases read as
        // plain calls; the pauser is a separate address because the whole point of
        // those cases is that the disable role cannot do what the admin role can.
        reg = new PqcAlgorithmRegistry(address(this), pauser);
    }

    // --- the packed word: one EXTSTATICCALL per claim is the registry's whole cost,
    // so the read interface must not be a struct.
    function test_readScheme_is_one_word_and_decodes() public view {
        uint256 w = reg.readScheme(MAYO2);
        (bool exists, bool enabled, uint8 venue, bool authorising, uint8 level) = PqcSchemeWord.unpack(w);
        assertTrue(exists);
        assertTrue(enabled);
        assertEq(venue, uint8(PqcAlgorithmRegistry.Venue.Offchain));
        assertFalse(authorising);                       // decision 13: MAYO authorises nothing
        assertEq(level, 2);
    }

    function test_readScheme_absent_row_is_exists_false_not_a_revert() public view {
        uint256 w = reg.readScheme(keccak256("nope"));
        (bool exists,,,,) = PqcSchemeWord.unpack(w);
        assertFalse(exists);
    }

    // --- the asymmetry the split exists for: abandon fast, adopt slowly.
    function test_disable_role_can_disable_immediately() public {
        vm.prank(pauser);
        reg.disable(MLDSA);
        assertFalse(reg.readEnabled(MLDSA));
    }

    function test_disable_role_can_never_enable_or_add_or_repurpose() public {
        vm.prank(pauser);
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.enable(MLDSA);
        vm.prank(pauser);
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.setParamHash(MLDSA, bytes32(uint256(7)));
        vm.prank(pauser);
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.addRow(keccak256("ml_dsa65"), uint8(2), bytes32(uint256(1)), address(0), 3);
    }

    function test_admin_enables_but_only_after_param_hash() public {
        // A row the constructor did not seed: fn_dsa512 IS seeded (disabled, but present), so
        // addRow on it reverts AlreadyPresent and the assertion below is never reached. ml_dsa65 is
        // the same unseeded id the disable-role test uses, and this contract is rebuilt in setUp().
        bytes32 fresh = keccak256("ml_dsa65");
        reg.addRow(fresh, uint8(2), bytes32(0), address(0), 5); // disabled at birth
        assertFalse(reg.readEnabled(fresh));
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.Unparameterized.selector, fresh));
        reg.enable(fresh);
        reg.setParamHash(fresh, bytes32(uint256(9)));
        reg.enable(fresh);
        assertTrue(reg.readEnabled(fresh));
    }

    // --- authorising is DERIVED, not stored (spec C4: a stored flag the mode does
    // not consult is a claim about capability that nothing checks).
    function test_authorising_tracks_the_mode_and_not_the_row_write() public {
        assertFalse(reg.isVerifiedNow(MLDSA));          // Default profile
        reg.setMode(PqcAlgorithmRegistry.Mode.Strong);
        assertTrue(reg.isVerifiedNow(MLDSA));           // same row, mode moved it
        reg.setMode(PqcAlgorithmRegistry.Mode.Default);
        assertFalse(reg.isVerifiedNow(MLDSA));
    }

    // The same property on the PACKED word, which is the only place Task 7's bridge
    // actually reads it from. `isVerifiedNow` above cannot see a defect in
    // `readScheme`'s authorising bit — measured 2026-11-13: replacing that bit with
    // `r.enabled` keeps the test above green — so the claim-time surface needs its
    // own red-capable case, asserted in both mode directions and for the row that
    // must stay non-authorising (mayo2) while Strong is on.
    function test_readScheme_authorising_bit_tracks_the_mode() public {
        bool authorising;
        (,, , authorising,) = PqcSchemeWord.unpack(reg.readScheme(MLDSA));
        assertFalse(authorising, "mldsa44 is authorising under Default");

        reg.setMode(PqcAlgorithmRegistry.Mode.Strong);
        (,, , authorising,) = PqcSchemeWord.unpack(reg.readScheme(MLDSA));
        assertTrue(authorising, "mldsa44 not authorising under Strong");

        // decision 13 in the packed word: the row Strong does not consult stays
        // non-authorising even while Strong is on, so the bridge can never read
        // "verify MAYO" out of this contract.
        (,, , authorising,) = PqcSchemeWord.unpack(reg.readScheme(MAYO2));
        assertFalse(authorising, "mayo2 must never be authorising");

        reg.setMode(PqcAlgorithmRegistry.Mode.Default);
        (,, , authorising,) = PqcSchemeWord.unpack(reg.readScheme(MLDSA));
        assertFalse(authorising, "leaving Strong must clear the bit");
    }

    function test_mode_is_admin_only_in_both_directions() public {
        vm.prank(pauser);
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.setMode(PqcAlgorithmRegistry.Mode.Strong);
    }

    // --- §7's mirror-image bug: a scheme off while the mode still claims it is
    // authorising must not be reachable.
    function test_disabling_the_mode_authorising_scheme_reverts_in_strong() public {
        reg.setMode(PqcAlgorithmRegistry.Mode.Strong);
        vm.prank(pauser);
        // abi.encodeWithSelector, not the bare .selector: the revert carries the scheme id, so a
        // 4-byte expectation never matches a 36-byte revert and the case would pass only by
        // accident. Pinning the id is also the stronger claim -- the guard must refuse THIS row.
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.WouldSkipVerification.selector, MLDSA));
        reg.disable(MLDSA);
    }

    function test_seeded_rows() public view {
        assertTrue(reg.readEnabled(keccak256("mayo2")));
        assertTrue(reg.readEnabled(keccak256("mldsa44")));
        assertFalse(reg.readEnabled(keccak256("fn_dsa512")));  // FIPS 206 not final
    }

    // --- the ML-DSA blob handle (Task 7's two extra registry reads). Plan 5 owns registering the
    // keys these point at; this plan owns that they are admin-written, read per index, and zero
    // until written -- because the bridge's Strong path refuses on zero, and a blob that defaulted
    // to something non-zero would turn that refusal into a verification against nothing.
    function test_mldsa_blob_defaults_to_zero_and_is_admin_written() public {
        assertEq(reg.mldsaBlobFor(0), address(0), "an unregistered blob is not zero");
        reg.setMldsaBlob(0, address(0xB10B));
        assertEq(reg.mldsaBlobFor(0), address(0xB10B));
        // per index, not one global pointer: index 1 is a different validator's key
        assertEq(reg.mldsaBlobFor(1), address(0), "setting one blob set another");
    }

    function test_mldsa_blob_overwrite_is_last_write_wins_and_emits() public {
        reg.setMldsaBlob(3, address(0xB10B));
        vm.expectEmit(true, false, false, true);
        emit PqcAlgorithmRegistry.MldsaBlobSet(3, address(0xC0DE));
        reg.setMldsaBlob(3, address(0xC0DE));
        assertEq(reg.mldsaBlobFor(3), address(0xC0DE));
    }

    function test_mldsa_blob_set_is_admin_only() public {
        vm.prank(pauser);
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.setMldsaBlob(0, address(0xB10B));
    }
}
