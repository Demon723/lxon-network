// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {PqcBridgeHarness} from "./PqcBridgeHarness.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";
import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";
import {MockVerifier} from "./MockVerifier.sol";
import {MockRegistry} from "./MockRegistry.sol";

/// DELTA-C6-4: the profile is read from the registry, once, at the top of the claim — and the
/// Strong path refuses rather than skipping. These are spec §10 decision 13's four cases plus the
/// failure modes of a dependency that is present but wrong.
///
/// The registry here is the REAL Task 2 registry for every case except two: an out-of-range mode
/// and a row that contradicts the mode are shapes it cannot produce, because its authorising bit
/// is derived from its own `_mode`. Those two go to PqcBridgeRegistryLieTest with a forwarding
/// mock, so even there the roster the binding reads is the real one.
contract PqcBridgeModeTest is PqcBridgeHarness {
    bytes32 internal bh = bytes32(uint256(0xB0));

    struct Claim {
        LXONPqcBridgeV1.Request r;
        bytes32 id;
        bytes[] sigs;
        bytes flat;
    }

    function setUp() public override {
        super.setUp();
        _configureInboundAndLock();
        // The mode the build ships in, stated rather than assumed: if Task 2's constructor ever
        // seeds Strong, every "default profile" case below silently becomes a Strong case.
        // Mode.Default is 0; assertEq has no enum overload, so the number is what is comparable.
        assertEq(uint256(registry.verifyMode()), 0, "registry does not ship Default");
    }

    /// The honest claim for `nonce`: a1 and a2 sign the ECDSA quorum, the bundle names the roster
    /// indices those keys actually hold, and the lattice leg is whatever the caller passes.
    /// Built BEFORE any expectRevert/expectCall is registered — the standing rule from Task 5,
    /// because this fixture makes two registry reads of its own and would otherwise spend the
    /// expectation the case is about.
    ///
    /// `srcTotalSent` is the LANE's running total, so it grows with the nonce: v4.1's exact-total
    /// check is `received + amount == srcTotalSent`, and a second claim that repeats the first
    /// claim's total is refused for the right reason (4 != 2+2) rather than reaching the check this
    /// case is about. Two claims in one test therefore need two different totals.
    function _prepare(uint256 nonce) internal view returns (Claim memory c) {
        c.r = _request(nonce, nonce * 2 ether, 2 ether, recipient);
        c.id = bridge.computeClaimId(c.r);
        uint256[] memory keys = _twoKeys();
        c.sigs = _signQuorum(c.id, bh, keys);
        c.flat = _flatBundle(c.id, bh, _indicesForKeys(keys), _two186());
    }

    /// Strong mode with the dependency wired: a verifier row, one blob per roster index in the
    /// quorum, and the mode flipped last so no half-wired state is ever claimed against.
    function _wireStrong(MockVerifier.Behaviour b) internal returns (MockVerifier v) {
        v = new MockVerifier();
        v.setBehaviour(b);
        registry.setVerifier(bridge.MLDSA44_ID(), address(v));
        registry.setMldsaBlob(0, address(v));
        registry.setMldsaBlob(1, address(v));
        registry.setMode(PqcAlgorithmRegistry.Mode.Strong);
    }

    /// The verifyMode field of the PqcBundleRecorded log for `id`, read from a log array the
    /// caller already took. Not expectEmit: claimTransfer emits BundleBindingChecked first and
    /// expectEmit binds to the NEXT log, so an expectEmit placed before the claim compares the
    /// wrong event and the case would only ever pass by coincidence of ordering. And not two
    /// getRecordedLogs() calls — the cheatcode DRAINS the buffer, so a second reader sees nothing
    /// and a "0 != 1" failure looks like a missing event. Measured that way today.
    function _loggedMode(Vm.Log[] memory logs, bytes32 id) internal pure returns (uint8) {
        bytes32 sig = LXONPqcBridgeV1.PqcBundleRecorded.selector;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig && logs[i].topics[1] == id) {
                (, uint8 m) = abi.decode(logs[i].data, (bytes32, uint8));
                return m;
            }
        }
        revert("no PqcBundleRecorded for this claim");
    }

    function _countLogs(Vm.Log[] memory logs, bytes32 sig, bytes32 id) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig && logs[i].topics[1] == id) n++;
        }
    }

    // (1) The default profile is a RULE, not an absence of one. A claim that carries lattice
    // signatures the contract chose not to check is the most misleading transaction this design
    // could produce: it LOOKS Strong to anyone reading the block. So it reverts. Never ignore.
    function test_default_mode_with_nonempty_mldsa_sigs_reverts() public {
        Claim memory c = _prepare(1);
        vm.expectRevert("default profile takes no lattice signatures");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        assertEq(bridge.pqcCommitment(c.id), bytes32(0), "a refused claim recorded a commitment");
        assertEq(token.balanceOf(recipient), 0, "a refused claim paid");
    }

    // The mirror of (1): the same request with an empty lattice leg DOES settle, so the refusal
    // above is about the signatures, not about the fixture being broken for everyone.
    function test_default_mode_with_empty_mldsa_sigs_settles() public {
        Claim memory c = _prepare(1);
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether);
    }

    // (2) The same bytes in Strong mode ARE verified — so a caller cannot confuse the profiles,
    // and the difference is the mode, not the payload.
    function test_strong_mode_with_the_same_bundle_verifies_and_settles() public {
        // One row name, two contracts: if the bridge's mirror ever diverges from the registry's
        // constant, _verifyLattice would read a row nobody registered and the profile would be
        // unfalsifiable rather than strongly verified.
        assertEq(bridge.MLDSA44_ID(), registry.MLDSA44_ID(), "bridge and registry name different rows");
        MockVerifier v = _wireStrong(MockVerifier.Behaviour.Accept);
        Claim memory c = _prepare(1);
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether, "Strong did not settle");
        assertEq(bridge.pqcCommitment(c.id), keccak256(c.flat));
        assertEq(uint256(v.behaviour()), uint256(MockVerifier.Behaviour.Accept), "wired the wrong verifier");
    }

    // (3) The mode used is in the log. A registry read tells a watcher what is true NOW; only the
    // claim's own event records what authorised it THEN.
    function test_recorded_mode_is_the_mode_at_settlement_not_at_read_time() public {
        Claim memory a = _prepare(1);
        vm.recordLogs();
        _claimFull(a.r, bh, a.sigs, new bytes[](0), a.flat);
        Vm.Log[] memory logsA = vm.getRecordedLogs();
        assertEq(_loggedMode(logsA, a.id), 0, "default claim logged a mode it did not use");

        _wireStrong(MockVerifier.Behaviour.Accept);
        Claim memory b = _prepare(2);
        vm.recordLogs();
        _claimFull(b.r, bh, b.sigs, _mldsa(2), b.flat);
        Vm.Log[] memory logsB = vm.getRecordedLogs();
        assertEq(_loggedMode(logsB, b.id), 1, "strong claim logged the mode it replaced");
    }

    // (4) Strong with no verifier wired — the state this build ships in, because C5 is Plan 5 —
    // must revert rather than settle. A scheme off that still moves money is §7's mirror-image
    // bug.
    function test_strong_mode_without_a_registered_verifier_reverts() public {
        registry.setMode(PqcAlgorithmRegistry.Mode.Strong);
        assertEq(registry.readVerifier(bridge.MLDSA44_ID()), address(0), "a verifier appeared");
        Claim memory c = _prepare(1);
        vm.expectRevert("strong mode without a verifier");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        assertEq(token.balanceOf(recipient), 0, "a claim Strong refused still paid");
    }

    // The same absent dependency on the default side, asserted as the control: the lattice row is
    // never consulted there, so an unwired verifier must not disturb it. This is what makes the
    // "skipped the lattice path" claim a measurement instead of a reading of the branch.
    function test_default_mode_settles_with_no_verifier_registered() public {
        assertEq(registry.readVerifier(bridge.MLDSA44_ID()), address(0));
        Claim memory c = _prepare(1);
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether, "default profile consulted the lattice row");
    }

    // Three failure modes of a verifier that EXISTS and is wrong. Written out one at a time: a
    // loop over revert reasons is how one of them stops being exercised, and these three differ
    // in exactly the way that matters — ok=true with no data, ok=false, and ok=true with data
    // that is not a bool.
    function test_strong_mode_treats_empty_return_data_as_false() public {
        _wireStrong(MockVerifier.Behaviour.EmptyReturn);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice verification failed");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    function test_strong_mode_treats_reverting_verifier_as_false() public {
        _wireStrong(MockVerifier.Behaviour.Revert);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice verification failed");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    function test_strong_mode_treats_unparsable_return_as_false() public {
        _wireStrong(MockVerifier.Behaviour.ShortReturn);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice verification failed");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    // The explicit reject is the fourth shape, and the only one that is a legitimate answer.
    function test_strong_mode_treats_an_explicit_rejection_as_false() public {
        _wireStrong(MockVerifier.Behaviour.Reject);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice verification failed");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    // Not 3, not threshold-1: one lattice signature per quorum member, in Strong, and the count
    // is checked before any verification so a wrong-shaped bundle is refused cheaply.
    function test_strong_mode_needs_exactly_threshold_lattice_sigs() public {
        _wireStrong(MockVerifier.Behaviour.Accept);
        Claim memory short_ = _prepare(1);
        vm.expectRevert("strong profile needs one per quorum member");
        _claimFull(short_.r, bh, short_.sigs, _mldsa(1), short_.flat);

        Claim memory long_ = _prepare(2);
        vm.expectRevert("strong profile needs one per quorum member");
        _claimFull(long_.r, bh, long_.sigs, _mldsa(3), long_.flat);
    }

    // The blob is the other half of the dependency: a verifier with nothing to verify against is
    // the same absent-scheme bug as a row with no verifier, and it must not be paid for.
    function test_strong_mode_without_a_registered_blob_reverts() public {
        MockVerifier v = new MockVerifier();
        registry.setVerifier(bridge.MLDSA44_ID(), address(v));
        registry.setMode(PqcAlgorithmRegistry.Mode.Strong);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice blob not registered for signer");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    // A signer whose roster slot has no blob is refused at THAT signer, not skipped — which is
    // why the blob is looked up per recovered address rather than once for the claim.
    function test_strong_mode_refuses_a_partial_blob_set() public {
        MockVerifier v = new MockVerifier();
        registry.setVerifier(bridge.MLDSA44_ID(), address(v));
        registry.setMldsaBlob(0, address(v));   // index 1 deliberately unwired
        registry.setMode(PqcAlgorithmRegistry.Mode.Strong);
        Claim memory c = _prepare(1);
        vm.expectRevert("lattice blob not registered for signer");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    // (9) History is written once. Flipping the mode after settlement must not re-open the claim,
    // must not rewrite the commitment, and must not re-authorise the money under a profile it was
    // not settled under.
    function test_mode_flip_after_settlement_does_not_rewrite_history() public {
        _wireStrong(MockVerifier.Behaviour.Accept);
        Claim memory c = _prepare(1);
        vm.recordLogs();
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 recorded = bridge.pqcCommitment(c.id);
        assertEq(_loggedMode(logs, c.id), 1);

        registry.setMode(PqcAlgorithmRegistry.Mode.Default);
        assertEq(bridge.pqcCommitment(c.id), recorded, "the commitment moved");
        assertEq(uint256(bridge.claimStatus(c.id)), uint256(LXONPqcBridgeV1.ClaimStatus.Completed));
        // The same calldata under the new profile: refused as already used, not re-evaluated.
        vm.expectRevert("already claimed");
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        assertEq(bridge.pqcCommitment(c.id), recorded, "a refused replay rewrote the commitment");
    }

    // (10) THE one registry read at the top. Default profile: exactly one verifyMode() call, and
    // the lattice row is not read at all — which the settle-without-a-verifier case above proves
    // from the other side, because a read here would have reverted.
    function test_registry_read_happens_once_per_claim() public {
        Claim memory c = _prepare(1);
        vm.expectCall(address(registry), abi.encodeWithSignature("verifyMode()"), 1);
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether, "the claim did not settle, so the count is vacuous");
    }

    // Strong legitimately reads more than the mode — the row, the verifier, a blob per signer —
    // and this is asserted separately so "one read at the top" cannot silently become "one read
    // ever". The mode read is still exactly one of them.
    function test_strong_mode_reads_the_mode_once_and_the_lattice_row_more() public {
        _wireStrong(MockVerifier.Behaviour.Accept);
        Claim memory c = _prepare(1);
        vm.expectCall(address(registry), abi.encodeWithSignature("verifyMode()"), 1);
        vm.expectCall(address(registry), abi.encodeCall(PqcAlgorithmRegistry.readScheme, (bridge.MLDSA44_ID())), 1);
        vm.expectCall(address(registry), abi.encodeCall(PqcAlgorithmRegistry.readVerifier, (bridge.MLDSA44_ID())), 1);
        vm.expectCall(address(registry), abi.encodeCall(PqcAlgorithmRegistry.mldsaBlobFor, (0)), 1);
        vm.expectCall(address(registry), abi.encodeCall(PqcAlgorithmRegistry.mldsaBlobFor, (1)), 1);
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether, "the claim did not settle, so the counts are vacuous");
    }

    // The binding event is the watcher's evidence that the same-party check ran. Emitting it
    // twice per claim — which is what Task 6's edit did — doubles every count in a monitor and
    // makes "one binding check" unreadable from the chain.
    function test_binding_event_is_emitted_once_per_claim() public {
        Claim memory c = _prepare(1);
        vm.recordLogs();
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, LXONPqcBridgeV1.BundleBindingChecked.selector, c.id), 1,
            "the binding check logged more than once");
        assertEq(_countLogs(logs, LXONPqcBridgeV1.PqcBundleRecorded.selector, c.id), 1,
            "the bundle recorded event is duplicated too");
    }
}

/// The two cases the real registry cannot produce, against a mock that forwards everything except
/// the mode and the packed word. Its bridge handle is asserted before each claim, because a mock
/// that is not actually in the loop makes both of these pass for the wrong reason.
contract PqcBridgeRegistryLieTest is PqcBridgeHarness {
    bytes32 internal bh = bytes32(uint256(0xB0));
    MockRegistry internal mock;

    function _registryHandleFor(address realRegistry) internal override returns (address) {
        mock = new MockRegistry(realRegistry);
        return address(mock);
    }

    struct Claim {
        LXONPqcBridgeV1.Request r;
        bytes32 id;
        bytes[] sigs;
        bytes flat;
    }

    function setUp() public override {
        super.setUp();
        _configureInboundAndLock();
        assertEq(bridge.registry(), address(mock), "the bridge is not reading the mock");
    }

    function _prepare(uint256 nonce) internal view returns (Claim memory c) {
        c.r = _request(nonce, nonce * 2 ether, 2 ether, recipient);
        c.id = bridge.computeClaimId(c.r);
        uint256[] memory keys = _twoKeys();
        c.sigs = _signQuorum(c.id, bh, keys);
        c.flat = _flatBundle(c.id, bh, _indicesForKeys(keys), _two186());
    }

    /// Control: with the mock answering mode 0 and forwarding the rest, an ordinary default claim
    /// settles — so a refusal in the two cases below is the mock's answer, not the fixture.
    function test_mock_registry_default_mode_still_settles() public {
        mock.setMode(0);
        Claim memory c = _prepare(1);
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
        assertEq(token.balanceOf(recipient), 2 ether);
    }

    /// A mode outside {Default, Strong} is not "the other branch". Guessing which profile an
    /// unrecognised word means is how a registry upgrade turns into an unverified settlement.
    function test_unrecognised_mode_is_refused_not_guessed() public {
        mock.setMode(2);
        Claim memory c = _prepare(1);
        vm.expectRevert("unknown verify mode");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
        vm.expectRevert("unknown verify mode");
        _claimFull(c.r, bh, c.sigs, new bytes[](0), c.flat);
    }

    /// The authorising bit is derived in THIS build, so nothing in the repo can make it disagree
    /// with the mode. The bridge still checks it, and this is the only input that can prove the
    /// check is live rather than decorative: mode Strong, row says the scheme is not authorising.
    function test_strong_mode_with_a_row_that_is_not_authorising_reverts() public {
        mock.setMode(1);
        // mayo2's own word: present, enabled, Offchain, and permanently non-authorising.
        mock.setRowWord(registry.readScheme(registry.MAYO2_ID()));
        registry.setVerifier(bridge.MLDSA44_ID(), address(new MockVerifier()));
        registry.setMldsaBlob(0, address(0xB10B));
        registry.setMldsaBlob(1, address(0xB10B));
        Claim memory c = _prepare(1);
        vm.expectRevert("registry mode says this row is not authorising");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }

    /// An all-zero word is "no such row": the bridge must name that, rather than reading present
    /// and enabled out of an uninitialised word and calling it a scheme.
    function test_strong_mode_with_an_absent_row_reverts() public {
        mock.setMode(1);
        mock.setRowWord(0);
        Claim memory c = _prepare(1);
        vm.expectRevert("mldsa44 row unavailable");
        _claimFull(c.r, bh, c.sigs, _mldsa(2), c.flat);
    }
}
