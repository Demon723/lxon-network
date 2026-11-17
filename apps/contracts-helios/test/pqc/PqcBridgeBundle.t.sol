// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PqcBridgeHarness} from "./PqcBridgeHarness.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";

/// Task 5: the bundle has exactly one form the contract accepts, the commitment is
/// computed in-contract, and the recorded bytes are the ones anyone can re-hash.
/// §10 item 21 is the reason this file exists: the same four fields serialize to 768
/// bytes flat and 800 bytes struct-wrapped, so a contract that hashed whatever
/// arrived would hold two commitments for one bundle.
contract PqcBridgeBundleTest is PqcBridgeHarness {
    bytes32 internal bh = bytes32(uint256(0xA5));

    function setUp() public override { super.setUp(); _configureInboundAndLock(); }

    // --- the malleability pair, first
    function test_canonical_bundle_is_768_bytes_at_threshold_two() public view {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes memory flat = bridge.canonicalBundle(
            LXONPqcBridgeV1.Bundle({claimId: id, srcBlockHash: bh, rosterIndices: _two(), mayoSigs: _two186()}));
        assertEq(flat.length, 768, "measured: 2 signatures of 186 B at threshold 2");
    }

    function test_struct_wrapped_bundle_reverts() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        LXONPqcBridgeV1.Bundle memory b =
            LXONPqcBridgeV1.Bundle({claimId: id, srcBlockHash: bh, rosterIndices: _two(), mayoSigs: _two186()});
        bytes memory wrapped = abi.encode(b);           // 800 B, decodes to the same fields
        assertEq(wrapped.length, 800, "the offset head a dynamic top-level argument adds");
        assertEq(abi.decode(wrapped, (LXONPqcBridgeV1.Bundle)).claimId, id,
            "the wrapped form decodes to the same bundle, which is why the contract must refuse it");
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        // The wrapped form cannot even be read as four flat fields, so the refusal is the
        // named error rather than the string used when the shape is right but the bytes are
        // not the canonical rendering of them. Both are refusals; only one of them is a
        // bare decoder revert, and that is the difference an operator sees in a log.
        vm.expectRevert(LXONPqcBridgeV1.BundleNotCanonical.selector);
        _claimFull(r, bh, sigs, new bytes[](0), wrapped);
    }

    // The accepted form settles, records keccak(canonical), and emits the same value
    // a watcher will recompute from the tx's own calldata.
    function test_flat_bundle_sets_the_commitment_and_emits_it() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes memory flat = _canonicalBundleFor(r, bh);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        vm.expectEmit(true, false, false, true);
        emit LXONPqcBridgeV1.PqcBundleRecorded(id, keccak256(flat), 0);
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(bridge.pqcCommitment(id), keccak256(flat), "commitment is keccak of the canonical form");
        assertEq(uint256(uint8(bridge.claimStatus(id))), uint256(uint8(LXONPqcBridgeV1.ClaimStatus.Completed)),
            "claim did not complete (forge has no assertEq overload for enums)");
    }

    // The commitment is computed by the contract. A caller-supplied hash would make the
    // requirement satisfiable by anyone controlling both sides of it — the mirror of the
    // keccak256(bundle) commitment with no reveal phase that spec §10 item 21 closed.
    // Derived from the canonical signature string, not recalled: a added or reordered
    // argument changes the selector and this fails.
    function test_no_argument_can_supply_the_commitment() public view {
        string memory sig = "claimTransfer((uint256,address,address,uint256,uint256,uint256,address,uint256,address,address,uint256),bytes32,bytes[],bytes[],bytes)";
        bytes4 derived = bytes4(keccak256(bytes(sig)));
        // type(...).f.selector, not this.f.selector: `this` is the TEST contract here. And it
        // is ambiguous at compile time if a 3-argument overload survives, which is the stronger
        // half of the claim.
        bytes4 live = LXONPqcBridgeV1.claimTransfer.selector;
        assertEq(uint256(bytes32(live)), uint256(bytes32(derived)),
            "claimTransfer's arity is no longer the recorded 5-argument form");
        // Nothing else to assert here: a second check comparing `derived` with itself would
        // be decoration, not a test. The load-bearing half is that
        // `type(LXONPqcBridgeV1).claimTransfer` resolves at all — with a 3-argument overload
        // still present it is ambiguous and this file does not compile, which is the same
        // fact stated by the compiler.
    }

    // Wrong claim id in a well-formed, canonical bundle.
    function test_bundle_bound_to_this_claim() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        LXONPqcBridgeV1.Request memory other = _request(2, 2 ether, 2 ether, recipient);
        // canonical for the OTHER claim, submitted against this one
        bytes memory flat = _canonicalBundleFor(other, bh);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        vm.expectRevert("bundle is not this claim");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(bridge.pqcCommitment(id), bytes32(0), "a refused claim must not record a commitment");
    }

    // Wrong block hash in a canonical bundle whose claim id is right.
    function test_bundle_bound_to_this_block_hash() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes32 wrongBh = bytes32(uint256(0xB0));
        LXONPqcBridgeV1.Bundle memory b = LXONPqcBridgeV1.Bundle({
            claimId: id, srcBlockHash: wrongBh, rosterIndices: _two(), mayoSigs: _two186()
        });
        bytes memory flat = bridge.canonicalBundle(b);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());   // sigs are over the RIGHT digest
        vm.expectRevert("bundle is not this block");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
    }

    // Short/long bundles are refused on size, not accidentally accepted by a decoder.
    function test_bundle_sizes_must_match_threshold() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        uint8[] memory oneIdx = new uint8[](1);
        oneIdx[0] = 0;
        bytes[] memory oneSig = new bytes[](1);
        oneSig[0] = _mayoStub(0x11);

        bytes memory shortIdx = abi.encode(id, bh, oneIdx, _two186());
        vm.expectRevert("bundle size does not match threshold");
        _claimFull(r, bh, sigs, new bytes[](0), shortIdx);

        bytes memory shortSigs = abi.encode(id, bh, _two(), oneSig);
        vm.expectRevert("bundle signatures do not match threshold");
        _claimFull(r, bh, sigs, new bytes[](0), shortSigs);
    }

    // The digests are family-distinct: no MAYO signature is ever interchangeable with an
    // ECDSA or ML-DSA one, and none of the three is the v4.1 digest.
    // A bundle that decodes to the SAME four fields but is not the canonical rendering of
    // them. Trailing padding is the cheapest example, and it is why the guard compares both
    // the length and the hash: a decoder that tolerates unused tail bytes would otherwise
    // hand one bundle a second commitment, which is §10 item 21 arriving from a different
    // direction than the struct wrap.
    function test_padded_bundle_is_refused() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes memory flat = _canonicalBundleFor(r, bh);
        bytes memory longer = bytes.concat(flat, new bytes(32));   // same four fields, extra tail
        assertEq(longer.length, flat.length + 32, "the fixture did not grow");
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        // Refused, whichever half of the guard catches it: either the decoder rejects the
        // tail or the canonical re-encoding mismatches. Both are refusals; an ACCEPTANCE here
        // would mean one claim id can carry two commitments.
        bool refused = false;
        try bridge.claimTransfer(r, bh, sigs, new bytes[](0), longer) { refused = false; }
        catch { refused = true; }
        assertTrue(refused, "a padded bundle was accepted: two commitments for one bundle");
        assertEq(bridge.pqcCommitment(id), bytes32(0), "the padded form must not have recorded");
    }

    // The commitment is computed by the contract from the bytes it accepted, so a caller
    // cannot pre-declare what will be checkable later.
    function test_commitment_matches_the_bytes_that_were_accepted() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes memory flat = _canonicalBundleFor(r, bh);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(bridge.pqcCommitment(id), keccak256(abi.encode(id, bh, _two(), _two186())),
            "commitment is not keccak of the flat encoding");
        // The claim settled and paid, which is what makes the commitment assertion a claim
        // about a live record rather than about a revert that never wrote anything.
        assertEq(token.balanceOf(recipient), 2 ether, "the settling claim did not pay");
    }

    function test_the_three_digest_domains_are_disjoint() public view {
        bytes32 id = keccak256("some claim id");
        bytes32 ecdsa = bridge.claimDigest(id, bh);
        bytes32 mayo = bridge.mayoDigest(id, bh);
        bytes32 mldsa = bridge.mldsaDigest(id, bh);
        assertTrue(ecdsa != mayo && ecdsa != mldsa && mayo != mldsa, "digest domains collide");
    }

    // Default profile refuses lattice signatures rather than ignoring them (spec decision:
    // silently dropping _mldsaSigs would let a caller believe Strong was in force).
    function test_default_profile_refers_lattice_signatures() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, recipient);
        bytes32 id = bridge.computeClaimId(r);
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        bytes memory flat = _canonicalBundleFor(r, bh);
        bytes[] memory one = new bytes[](1);
        one[0] = new bytes(2420);
        vm.expectRevert("default profile takes no lattice signatures");
        _claimFull(r, bh, sigs, one, flat);
    }
}
