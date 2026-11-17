// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PqcBridgeHarness} from "./PqcBridgeHarness.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";

/// DELTA-C6-3: the recorded bundle has to attest the same validators whose secp256k1
/// signatures just recovered. This is the only NEW check in the claim path, and the
/// property the 32-byte commitment design could not express at all — there was nothing
/// to look at.
contract PqcBridgeBindingTest is PqcBridgeHarness {
    bytes32 internal bh = bytes32(uint256(0xB0));

    function setUp() public override { super.setUp(); _configureInboundAndLock(); }

    function _idx(uint8 a, uint8 b) internal pure returns (uint8[] memory k) {
        k = new uint8[](2);
        k[0] = a; k[1] = b;
    }

    // The honest case: a1 (roster 0) and a2 (roster 1) sign, and the bundle says {0,1}.
    function test_binding_accepts_indices_that_match_the_recovered_signers() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        uint256[] memory keys = _twoKeys();
        bytes[] memory sigs = _signQuorum(id, bh, keys);
        bytes memory flat = _flatBundle(id, bh, _indicesForKeys(keys), _two186());
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(token.balanceOf(recipient), 2 ether, "the honest bundle did not settle");
        assertEq(bridge.pqcCommitment(id), keccak256(flat));
    }

    // The whole reason the check exists. a1 (0) and a3 (2) sign; the bundle credits {0,1},
    // and index 1 is a2, who did not sign. (The plan's draft comment described this the
    // other way round against its own fixture; the code above is the measured case.)
    function test_binding_rejects_indices_outside_the_recovered_set() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        uint256[] memory keys = new uint256[](2);
        keys[0] = a1.key; keys[1] = a3.key;
        bytes[] memory sigs = _signQuorum(id, bh, keys);
        bytes memory flat = _flatBundle(id, bh, _idx(0, 1), _two186());
        vm.expectRevert("bundle indices not the recovered signers");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(bridge.pqcCommitment(id), bytes32(0), "a misattributed bundle recorded anyway");
    }

    // Index 9 was never rostered: rosterValidator(9) == address(0), so it cannot name a
    // signer. Silence here would be the "index 0 for an unrostered address" bug recurring.
    function test_binding_rejects_an_index_with_no_roster_entry() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        uint256[] memory keys = _twoKeys();
        bytes[] memory sigs = _signQuorum(id, bh, keys);
        bytes memory flat = _flatBundle(id, bh, _idx(0, 9), _two186());
        vm.expectRevert("bundle index not a roster entry");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
    }

    // {0,0} at threshold 2 credits ONE validator for the whole quorum. Found while writing
    // this case: with a pure membership test both slots resolve to a1, who is in the
    // recovered set, so the bundle passes and the attribution is a lie. Hence distinctness
    // and the exact-set requirement in _requireBundleBoundToSigners.
    function test_binding_rejects_duplicates_and_a_short_index_array() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        uint256[] memory keys = _twoKeys();
        bytes[] memory sigs = _signQuorum(id, bh, keys);

        bytes memory dup = _flatBundle(id, bh, _idx(0, 0), _two186());
        vm.expectRevert("bundle indices contain a duplicate");
        _claimFull(r, bh, sigs, new bytes[](0), dup);

        uint8[] memory one = new uint8[](1);
        one[0] = 0;
        bytes memory shorty = _flatBundle(id, bh, one, _two186());
        vm.expectRevert("bundle size does not match threshold");
        _claimFull(r, bh, sigs, new bytes[](0), shorty);
    }

    // The check compares indices to ADDRESSES, so a MAYO key rotation cannot break it --
    // the property that keeps roster history a C8/watcher concern rather than a claim-time
    // dependency. Same validators, new keys, same claim settles.
    function test_binding_survives_a_key_rotation() public {
        registry.retireRosterKey(0, 500);
        registry.setRosterKey(0, a1.addr, _rosterKey(0x77), 501);

        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        uint256[] memory keys = _twoKeys();
        bytes[] memory sigs = _signQuorum(id, bh, keys);
        bytes memory flat = _flatBundle(id, bh, _indicesForKeys(keys), _two186());
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(token.balanceOf(recipient), 2 ether, "rotation broke the same-party check");
        assertEq(uint256(registry.rosterKeyHistoryLength(0)), 2, "history must keep the retired key");
    }

    // A bridge deployed with no registry cannot be built; the alternative -- a zero handle
    // that reads address(0) and gets empty code back -- is the codeless-target trap that
    // turns a roster lookup into a silent pass.
    function test_roster_ref_is_immutable_and_required() public {
        address[] memory set = new address[](3);
        set[0] = a1.addr; set[1] = a2.addr; set[2] = a3.addr;
        vm.expectRevert("registry is zero");
        new LXONPqcBridgeV1(address(0), 0, TIMETIME, set, 2, 1 ether, 1e24, address(0));
        assertEq(bridge.registry(), address(registry), "the handle moved; it is immutable");
    }
}
