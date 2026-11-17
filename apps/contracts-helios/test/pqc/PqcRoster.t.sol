// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";

contract PqcRosterTest is Test {
    PqcAlgorithmRegistry reg;
    address v1 = address(0xB1);
    address v2 = address(0xB2);
    address v3 = address(0xB3);
    bytes keyOld;
    bytes keyNew;

    function _mkbytes(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(4912);
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }

    function setUp() public {
        // admin = this contract, so the roster's admin-path writes are plain calls;
        // pauser stays a different address because one case proves it cannot write.
        reg = new PqcAlgorithmRegistry(address(this), address(0x9A15E));
        keyOld = _mkbytes(0x11);
        keyNew = _mkbytes(0x22);
    }

    function test_set_then_read_both_directions() public {
        reg.setRosterKey(0, v1, keyOld, 100);
        // The absent case is asserted FIRST on purpose. With the bare-slot decoding the plan named,
        // rosterIndexOf(v1) returns 1 and this test dies on "1 != 0" three lines early, never reaching
        // the assertion that states the actual hazard — an unrostered address reporting index 0, which
        // Task 6's binding check would accept. Measured 2026-11-13 by planting exactly that mutation.
        assertEq(int256(reg.rosterIndexOf(address(0xDEAD))), -1, "absent must be -1, not 0");
        assertEq(reg.rosterValidator(0), v1);
        assertEq(int256(reg.rosterIndexOf(v1)), 0, "index 0 must be representable, not read as absent");
    }

    function test_binding_needs_the_address_not_the_key_so_a_rotation_does_not_move_it() public {
        reg.setRosterKey(0, v1, keyOld, 100);
        reg.retireRosterKey(0, 250);
        reg.setRosterKey(0, v1, keyNew, 251);
        assertEq(reg.rosterValidator(0), v1, "the address is what C6 compares; it must survive rotation");
    }

    function test_key_history_is_append_only_and_block_addressable() public {
        reg.setRosterKey(0, v1, keyOld, 100);
        reg.retireRosterKey(0, 250);
        reg.setRosterKey(0, v1, keyNew, 251);
        assertEq(keccak256(reg.keyAt(0, 150)), keccak256(keyOld), "claim at 150 must resolve the OLD key");
        assertEq(keccak256(reg.keyAt(0, 300)), keccak256(keyNew), "and the new one at 300");
        // abi.encodeWithSelector, not the bare .selector (the same correction Task 2 needed, and
        // measured here first: the contract reverts RosterGap(0, 99) and a 4-byte expectation still
        // fails). Pinning the arguments is also the stronger claim -- a gap at the WRONG block or the
        // wrong index is a different bug, and the bare selector would accept it.
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.RosterGap.selector, 0, uint256(99)));
        reg.keyAt(0, 99);   // before any key existed: an error, not empty bytes
    }

    function test_retired_keys_are_never_dropped() public {
        reg.setRosterKey(0, v1, keyOld, 100);
        reg.retireRosterKey(0, 250);
        reg.setRosterKey(0, v1, keyNew, 251);
        assertEq(reg.rosterKeyHistoryLength(0), 2, "dropping history makes the detection window for past claims exactly zero");
    }

    function test_roster_writes_are_admin_only_and_index_bounded() public {
        vm.prank(address(0x9A15E));
        vm.expectRevert(PqcAlgorithmRegistry.NotAdmin.selector);
        reg.setRosterKey(1, v2, keyOld, 1);
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.RosterTooLarge.selector, 16));
        reg.setRosterKey(16, v3, keyOld, 1);
    }

    function test_key_length_is_the_ruled_revision_not_prose() public {
        bytes memory wrong = new bytes(2928);   // the Round-3 tip size; decision 15 ruled 4,912
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.BadKeyLength.selector, uint256(2928)));
        reg.setRosterKey(0, v1, wrong, 1);
    }

    function test_a_second_validator_taking_an_used_address_reverts() public {
        reg.setRosterKey(0, v1, keyOld, 1);
        vm.expectRevert(abi.encodeWithSelector(PqcAlgorithmRegistry.RosterAddressTaken.selector, v1));
        reg.setRosterKey(1, v1, keyNew, 1);
    }
}
