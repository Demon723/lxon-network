// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PqcBridgeHarness} from "./PqcBridgeHarness.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";

/// C6 is a copy, so this file's job is to prove the copy kept v4.1's rules — the
/// ones whose violation moved money once already. Each case names the v4.1 line
/// it is holding, resolved against reference/LXONAttestedBridgeV41.sol.
contract PqcBridgeBaseTest is PqcBridgeHarness {
    function setUp() public override { super.setUp(); }

    // The harness's chain id is the CLAIM side (destChainId == block.chainid), and v4.1 refuses a
    // lock whose destination is this chain ("self chain"). So the lock test moves the EVM to the
    // source chain first — one bridge instance is one side of a lane, and pretending otherwise is
    // how a copy's tests end up asserting a route that the contract would never serve.
    function test_lock_advances_lane_and_escrow() public {
        vm.chainId(SRC_CHAIN);
        token.mint(address(this), 5 ether);
        token.approve(address(bridge), 5 ether);
        bridge.setPeer(DEST_CHAIN, address(0xBEEF));           // onlyConfigurer path, pre-seal
        bridge.setOutbound(DEST_CHAIN, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        bytes32 id = bridge.lockTransfer(address(token), 2 ether, DEST_CHAIN, address(0xC0DE));
        assertEq(bridge.laneNonce(DEST_CHAIN, address(token)), 1);
        assertEq(bridge.escrowed(address(token)), 2 ether);
        assertEq(bridge.totalSentFor(DEST_CHAIN, address(token)), 2 ether);
        assertTrue(id != bytes32(0));
    }

    // V41:490. v4's own comment records that `==` mutated to `>=` survived every v4
    // test, which is why this is a test and not a sentence.
    function test_claim_rejects_a_total_that_is_short() public {
        _configureMintInbound(10 ether);
        LXONPqcBridgeV1.Request memory r = _request(1, 3 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        // The bundle is built BEFORE expectRevert on purpose: `_claim` reaches the bridge for
        // computeClaimId, and forge hands the very next call the pending expectation, so a seam
        // that makes its own read would have that read judged instead of the claim. Measured
        // 2026-11-13: all three refusal cases here reported "next call did not revert as
        // expected" until they were rewritten to call _claimFull with the bytes already in hand.
        // Standing rule for Tasks 6-9: a refusal test never calls `_claim`.
        bytes memory flat = _canonicalBundleFor(r, bh);
        vm.expectRevert("total mismatch");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
    }

    // The same bundle with an EXACT total settles: the guard is about the relation,
    // not about the amounts, and without this row the short case above would pass on
    // any route that could never pay at all.
    function test_claim_settles_when_the_total_is_exact() public {
        _configureMintInbound(10 ether);
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        _claim(r, bh, _signQuorum(id, bh, _twoKeys()));
        assertEq(token.balanceOf(address(0xC0DE)), 2 ether);
        assertEq(bridge.totalReceivedFrom(SRC_CHAIN, address(token)), 2 ether);
        assertEq(bridge.blockHashAttested(id), bh);
    }

    // The OTHER direction, and the one that matters: `>=` survives a short total (above), so a
    // suite that only tests "less than" is a suite that passes on the mutation. Minting MORE than
    // the lane ever sent is the hole v4's comment describes, and it is only visible when the claim
    // over-pays. Measured 2026-11-13: with `==` mutated to `>=` in claimTransfer, every case above
    // stayed green; this one is what kills it.
    function test_claim_rejects_an_amount_over_the_lane_total() public {
        _configureMintInbound(10 ether);
        LXONPqcBridgeV1.Request memory r = _request(1, 1 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        bytes memory flat = _canonicalBundleFor(r, bh);
        vm.expectRevert("total mismatch");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(token.balanceOf(address(0xC0DE)), 0, "a refused claim minted anyway");
        assertEq(bridge.totalReceivedFrom(SRC_CHAIN, address(token)), 0);
    }

    // V41:388, 389
    function test_below_threshold_and_below_quorum_floor_both_revert() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory one = _signQuorum(id, bh, _oneKey());
        vm.expectRevert("below threshold");
        bridge.verifyBundle(id, bh, one);
        // quorumFloor() = 3/2+1 = 2, so a two-signature bundle passes the floor and
        // a one-signature bundle stops at the threshold guard first. The ordering is
        // asserted here so a future swap of the two requires is visible.
        assertEq(bridge.quorumFloor(), 2, "floor moved; the ordering claim above needs re-reading");
        assertEq(bridge.threshold(), 2);
    }

    // V41:396 strictly ascending.
    function test_duplicate_and_descending_signers_revert() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory dup = new bytes[](2);
        bytes[] memory good = _signQuorum(id, bh, _twoKeys());
        dup[0] = good[0];
        dup[1] = good[0];   // same signer twice
        vm.expectRevert("signers not ascending");
        bridge.verifyBundle(id, bh, dup);
        bytes[] memory desc = _signQuorumDescending(id, bh);
        vm.expectRevert("signers not ascending");
        bridge.verifyBundle(id, bh, desc);
    }

    // V41:397 — the quorum must be admissible, not merely role-bearing (review M9).
    // The outsider address is a well-formed, ascending signer that was never added to
    // the validator set, so the ONLY thing that can refuse it is isAdmissible.
    // (The other branch of that predicate — validator but staked below minStake —
    // cannot be reached in this harness: minStake is 0 here, the Polygon-side shape,
    // and slashing is onlyTimelock. It needs a minStake>0 deployment, and the plan's
    // drafted `bridge.slashValidator(...)` line did neither, so it is not silently
    // carried: see the Task 4 note in the plan.)
    function test_inadmissible_signer_reverts() public {
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeysIncludingOutsider());
        vm.expectRevert("signer not an admissible validator");
        bridge.verifyBundle(id, bh, sigs);
    }

    // V41:505 Release-branch escrow check: a Release route may never pay out more
    // than the escrow actually holds, and the check runs before the transfer.
    //
    // The ORDER here is not cosmetic, and two failures taught it: `lockTransfer` calls
    // `_markUsed()`, which sets `configSealed`, so every route this test needs must be
    // configured BEFORE the lock that builds the escrow — configuring afterwards reverts
    // "not configured yet". And the lock cannot go to this chain ("self chain"), so it
    // goes to a third chain id; `escrowed` is keyed by token, not by lane, which is
    // exactly why the Release branch can be starved by a lock on an unrelated lane.
    function test_release_payout_short_escrow_reverts() public {
        token.mint(address(this), 5 ether);
        token.approve(address(bridge), 5 ether);
        bridge.setPeer(SRC_CHAIN, address(0xBEEF));
        bridge.setInbound(SRC_CHAIN, address(token), address(token), LXONPqcBridgeV1.Payout.Release, 10 ether, true);
        bridge.setPeer(999, address(0xBEE9));
        bridge.setOutbound(999, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        bridge.lockTransfer(address(token), 1 ether, 999, address(0xC0DE));
        assertTrue(bridge.configSealed(), "the escrow-building lock should have sealed config");
        assertEq(bridge.escrowed(address(token)), 1 ether, "escrow did not build as the route needs");

        // Exact total, so the guard under test is the escrow check and not the ledger one.
        LXONPqcBridgeV1.Request memory r = _request(2, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        bytes[] memory sigs = _signQuorum(id, bh, _twoKeys());
        uint256 before = token.balanceOf(address(0xC0DE));
        bytes memory flat = _canonicalBundleFor(r, bh);
        vm.expectRevert("escrow short");
        _claimFull(r, bh, sigs, new bytes[](0), flat);
        assertEq(token.balanceOf(address(0xC0DE)), before, "a refused claim must not have paid");
    }

    // V41:492/328-331: the first completed claim self-seals the config path.
    function test_first_claim_seals_config() public {
        assertFalse(bridge.configSealed(), "sealed before anything happened");
        _configureMintInbound(10 ether);
        LXONPqcBridgeV1.Request memory r = _request(1, 2 ether, 2 ether, address(0xC0DE));
        bytes32 id = bridge.computeClaimId(r);
        bytes32 bh = bytes32(uint256(0xABC));
        _claim(r, bh, _signQuorum(id, bh, _twoKeys()));
        assertTrue(bridge.configSealed(), "the first completed claim must seal the config path");
        // and sealing is not cosmetic: the same key can no longer configure a route
        vm.expectRevert("not configured yet");
        bridge.setPeer(999, address(0xdead));
    }
}
