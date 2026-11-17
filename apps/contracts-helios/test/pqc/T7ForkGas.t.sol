// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";
import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";
import {LXONTestToken} from "./LXONTestToken.sol";

/// A sink that makes the individual terms inside the C6 delta measurable rather than assumed.
/// Every entry point does ONE chargeable thing, so bracketing it from the test gives the same
/// quantity the claim path pays for. It is not the claim, and nothing here claims it is: the
/// component figures are labelled by what they isolate, and the total comes from the bridge.
contract T7GasProbe {
    event Probe(bytes32 indexed a, bytes32 b, bytes32 c);

    mapping(bytes32 => bytes32) public slots;

    /// zero -> non-zero: the SSTORE class `pqcCommitment[id] = bundleHash` belongs to.
    function writeCold(bytes32 k, bytes32 v) external {
        slots[k] = v;
    }

    /// indexed topic + two 32-byte data words: the shape of PqcBundleRecorded.
    function logRecord() external {
        emit Probe(bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)));
    }

    /// Calibration. A body that reads nothing, writes nothing, logs nothing and returns nothing,
    /// so a bracket around a call to this is the CALL FLOOR of the measuring rig itself, not a
    /// property of the bridge. Every component figure below is printed raw and net of it, and the
    /// floor is printed twice in the same test so that whether it is a constant or a function of
    /// the caller's remaining gas is a measurement rather than an assumption.
    function empty() external {}
}

/// T7 — Plan 2 Task 8. The claim-shape measurements.
///
/// Run against a LOCAL anvil fork: `T7_FORK_URL=<rpc> forge test --match-path
/// 'test/pqc/T7ForkGas.t.sol'`. The fork supplies the real chain id, block base, gas limit and
/// base fee; every transaction here is signed by a key this file derives inside the EVM test
/// process, and nothing is broadcast to a real RPC. That distinction is the whole of the
/// deploy-nothing rule, so it is stated at the top of the file rather than assumed.
///
/// If T7_FORK_URL is unset, T7_CHAIN_ID must be set and the figures are taken on the LOCAL test
/// EVM with that chain id. Those are still real EVM gas numbers — the state-trie shape, the
/// precompile set and the base fee of the live chain are what a fork adds, and the file labels
/// which context produced which figure so a local number can never be read as a forked one.
///
/// WHAT IS AND IS NOT MEASURED, stated before any table is filled from this run:
///   measured   — gasleft() brackets around the calls below, on this chain context.
///   NOT here   — the 21,000 intrinsic and the per-byte INTRINSIC calldata charge. A forge test
///                call is an internal-to-external CALL, not a transaction, so those charges never
///                appear in these numbers. They are charged by a real tx on top, and the
///                fork-gas.sh companion computes them from the measured byte counts.
contract T7ForkGasTest is Test {
    LXONPqcBridgeV1 internal bridge;
    PqcAlgorithmRegistry internal registry;
    LXONTestToken internal token;
    T7GasProbe internal probe;

    uint256 internal destChain;
    uint256 internal srcChain;
    address internal constant SRC_BRIDGE = address(0xBEEF);
    address internal recipient = address(0xC0DE);

    uint256 internal k1 = 0xA11CE;
    uint256 internal k2 = 0xB0b;
    uint256 internal k3 = 0xC0FFEE;

    bytes32 private constant BH = bytes32(uint256(0xB0));
    uint256 internal constant AMOUNT = 2 ether;

    function setUp() public {
        string memory url = vm.envOr("T7_FORK_URL", string(""));
        // No env var means the ordinary `forge test --match-path 'test/pqc/*'` gate runs this file
        // too, and a gate that needs an RPC to stay green is a gate that gets skipped. So the
        // default is a LOCAL context on 137 — the same EVM, the same chain id, without the
        // network — and every figure says which context produced it. A fork run is what
        // fork-gas.sh asks for, and it is labelled FORK at the top of its own output.
        uint256 forced = vm.envOr("T7_CHAIN_ID", uint256(137));
        if (bytes(url).length > 0) {
            vm.createSelectFork(url);
            console2.log("context: FORK", url);
        } else {
            vm.chainId(forced);
            console2.log("context: LOCAL, no fork, chain id forced to", forced);
        }

        destChain = block.chainid;
        // One instance is one side of a lane: the source of a claim is always the OTHER chain.
        srcChain = destChain == 137 ? 724 : 137;
        console2.log("dest chain id:", destChain, "src chain id:", srcChain);
        console2.log("block number:", block.number);
        console2.log("block gaslimit:", block.gaslimit);
        console2.log("block basefee:", block.basefee);

        token = new LXONTestToken();
        registry = new PqcAlgorithmRegistry(address(this), address(this));
        address[] memory set = new address[](3);
        set[0] = vm.addr(k1);
        set[1] = vm.addr(k2);
        set[2] = vm.addr(k3);
        bridge = new LXONPqcBridgeV1(address(0), 0, address(this), set, 2, 1 ether, 1e24,
            address(registry));
        token.setBridge(address(bridge));
        probe = new T7GasProbe();

        registry.setRosterKey(0, vm.addr(k1), _key(0x11), block.number);
        registry.setRosterKey(1, vm.addr(k2), _key(0x22), block.number);
        registry.setRosterKey(2, vm.addr(k3), _key(0x33), block.number);

        bridge.setPeer(srcChain, SRC_BRIDGE);
        bridge.setInbound(srcChain, address(token), address(token), LXONPqcBridgeV1.Payout.Mint,
            1000 ether, true);
    }

    function _key(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(4912);                     // MAYO_PK_BYTES at the ruled revision
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }

    function _mayo(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(186);                      // MAYO_2 signature, T2 row 23
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }

    function _request(uint256 nonce) internal view returns (LXONPqcBridgeV1.Request memory r) {
        r = LXONPqcBridgeV1.Request({
            srcChainId: srcChain,
            srcBridge: SRC_BRIDGE,
            destBridge: address(bridge),
            destChainId: destChain,
            laneNonce: nonce,
            srcTotalSent: nonce * AMOUNT,
            srcToken: address(token),
            amount: AMOUNT,
            sender: address(0xD000),
            recipient: recipient,
            srcBlock: 1_000
        });
    }

    /// The honest quorum: two signatures strictly ascending by recovered address, plus the
    /// canonical bundle naming the roster indices those two keys actually hold.
    struct Fixture {
        LXONPqcBridgeV1.Request r;
        bytes32 id;
        bytes[] sigs;
        uint8[] idx;
        bytes[] mayoSigs;
        bytes bundle;
    }

    function _fixture(uint256 nonce) internal view returns (Fixture memory f) {
        f.r = _request(nonce);
        f.id = bridge.computeClaimId(f.r);
        bytes32 digest = bridge.claimDigest(f.id, BH);

        address s1 = vm.addr(k1);
        address s2 = vm.addr(k2);
        uint256 keyA = k1;
        uint256 keyB = k2;
        if (s2 < s1) {
            (s1, s2) = (s2, s1);
            (keyA, keyB) = (keyB, keyA);
        }
        require(s1 != s2, "fixture keys collide");

        f.sigs = new bytes[](2);
        f.sigs[0] = _sig(keyA, digest);
        f.sigs[1] = _sig(keyB, digest);

        f.idx = new uint8[](2);
        // The roster index of whoever is in each signature slot, so the bundle names the parties
        // that signed rather than a permutation that happens to pass.
        f.idx[0] = s1 == vm.addr(k1) ? 0 : 1;
        f.idx[1] = s2 == vm.addr(k1) ? 0 : 1;

        f.mayoSigs = new bytes[](2);
        f.mayoSigs[0] = _mayo(0x11);
        f.mayoSigs[1] = _mayo(0x22);
        f.bundle = abi.encode(f.id, BH, f.idx, f.mayoSigs);
    }

    function _sig(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// THE headline figures. Two methodology decisions, both stated because both change the number:
    ///
    /// (1) The calldata is encoded OUTSIDE the bracket and sent with one `address(bridge).call(cd)`.
    ///     Calling `bridge.claimTransfer(f.r, ...)` directly puts the test contract's own argument
    ///     encoding inside the figure, and that is not part of what a chain executes per claim.
    /// (2) TWO claims are measured, not one. A claim writes three per-id slots
    ///     (claimStatus, blockHashAttested, pqcCommitment) that are cold on the first claim of any
    ///     id and cold again on the second, but the lane slots, the route struct and the token's
    ///     totals warm after the first. A single figure cannot answer "what does a claim cost",
    ///     because the answer differs by tens of thousands of gas depending on which state is being
    ///     paid for. The derived row in §6.3 does not say which it was, which is the first thing
    ///     this task had to find out.
    ///
    /// Still NOT in these numbers: the 21,000 transaction base and the per-byte intrinsic calldata
    /// charge. A forge test call is not a transaction. fork-gas.sh adds them from the byte count
    /// this file prints, and the table says so.
    function _claimGas(Fixture memory f, string memory which) internal returns (uint256 used, uint256 cdBytes) {
        bytes memory cd = abi.encodeCall(
            LXONPqcBridgeV1.claimTransfer, (f.r, BH, f.sigs, new bytes[](0), f.bundle));
        cdBytes = cd.length;
        uint256 before = gasleft();
        (bool ok, ) = address(bridge).call(cd);
        used = before - gasleft();
        // Not expectRevert-shaped: a reverted bracket measures the gas of a failure, which is a
        // different quantity and would otherwise be printed as if it were the claim.
        require(ok, string.concat("the measured claim reverted; this figure is not a claim cost: ", which));
    }

    function _bracket(address target, bytes memory cd, string memory what) internal returns (uint256) {
        uint256 before = gasleft();
        (bool ok, ) = target.call(cd);
        uint256 used = before - gasleft();
        // The `what` label is load-bearing: a bare "bracket reverted" on a six-call test is a
        // mystery, and the first run of this file produced exactly that.
        require(ok, string.concat("bracket reverted at: ", what));
        return used;
    }

    /// One bracket around probe.empty(): the rig's own floor, measured where it is used.
    function _floor() internal returns (uint256 floor, uint256 callerGasLeft) {
        uint256 before = gasleft();
        callerGasLeft = before;
        (bool ok, ) = address(probe).call(abi.encodeWithSelector(T7GasProbe.empty.selector));
        require(ok, "calibration bracket reverted");
        floor = before - gasleft();
    }

    function test_claim_gas_at_threshold_two() public {
        Fixture memory f1 = _fixture(1);
        assertEq(f1.bundle.length, 768, "if this moved, the ruled 186 B signature assumption broke");

        (uint256 firstClaim, uint256 cdBytes) = _claimGas(f1, "headline 1");
        assertEq(token.balanceOf(recipient), AMOUNT, "the measured claim did not settle");

        Fixture memory f2 = _fixture(2);
        (uint256 secondClaim, ) = _claimGas(f2, "headline 2");
        assertEq(token.balanceOf(recipient), 2 * AMOUNT, "the second claim did not settle");

        // Direction asserted, not narrated: if the steady-state claim were NOT cheaper, the
        // cold/warm split below would be a story rather than a measurement.
        assertLt(secondClaim, firstClaim, "the second claim was not cheaper; re-read the decomposition");

        console2.log("claim 1 of a lane, EVM-side gas:", firstClaim);
        console2.log("claim 2 of the same lane, EVM-side gas:", secondClaim);
        console2.log("difference explained by state rent:", firstClaim - secondClaim);
        console2.log("claimTransfer calldata bytes (tx args, incl. selector):", cdBytes);
        console2.log("bundle bytes inside it:", f1.bundle.length);
        console2.log("chain id this figure was taken on:", destChain);
        console2.log("basefee at this block:", block.basefee);
        if (bytes(vm.envOr("T7_FORK_URL", string(""))).length > 0) {
            console2.log("forked this run: true");
        } else {
            console2.log("forked this run: false");
        }
    }

    /// The terms the derived row has no measured counterpart for, each isolated in its own bracket
    /// and each measured TWICE — once against cold state and once against warm — because the single
    /// number a table wants depends on which of the two it is, and the plan never said.
    function test_c6_component_terms() public {
        Fixture memory f = _fixture(1);

        // The rig's floor, taken FIRST and again LAST. If the two differ, the floor is a function
        // of the caller's remaining gas and every raw number below has to be read against the
        // floor printed beside it; if they agree, it is a constant and the net column is exact.
        (uint256 floorFirst, uint256 gasAtFirst) = _floor();

        bytes memory cdCanonical =
            abi.encodeWithSelector(LXONPqcBridgeV1.canonicalBundle.selector, _asBundle(f));
        uint256 canonicalCold = _bracket(address(bridge), cdCanonical, "canonicalBundle");
        uint256 canonicalWarm = _bracket(address(bridge), cdCanonical, "canonicalBundle warm");

        bytes memory cdDecode =
            abi.encodeWithSelector(LXONPqcBridgeV1.decodeBundleFlat.selector, f.bundle);
        uint256 decodeCold = _bracket(address(bridge), cdDecode, "decodeBundleFlat");
        uint256 decodeWarm = _bracket(address(bridge), cdDecode, "decodeBundleFlat warm");

        bytes32 slotKey = keccak256("t7.cold.slot");
        bytes memory cdWrite = abi.encodeCall(T7GasProbe.writeCold, (slotKey, bytes32(uint256(0xA9))));
        uint256 sstoreCold = _bracket(address(probe), cdWrite, "writeCold");
        uint256 sstoreWarm = _bracket(address(probe), cdWrite, "writeWarm");   // same key, non-zero -> non-zero

        bytes memory cdLog = abi.encodeWithSelector(T7GasProbe.logRecord.selector);
        uint256 eventCold = _bracket(address(probe), cdLog, "logRecord");
        uint256 eventWarm = _bracket(address(probe), cdLog, "logRecord warm");

        bytes memory cdRoster = abi.encodeCall(PqcAlgorithmRegistry.rosterValidator, (uint8(0)));
        uint256 rosterCold = _bracket(address(registry), cdRoster, "rosterValidator");
        uint256 rosterWarm = _bracket(address(registry), cdRoster, "rosterValidator warm");

        // The hashing term the recording pays, measured in the test contract rather than asserted
        // from a formula: one keccak over exactly the bundle the claim carries.
        uint256 kBefore = gasleft();
        bytes32 h = keccak256(f.bundle);
        uint256 gKeccak = kBefore - gasleft();
        assertEq(h, keccak256(abi.encode(f.id, BH, f.idx, f.mayoSigs)), "fixture is not its own bundle");

        console2.log("canonicalBundle 768 B out, cold callee:", canonicalCold);
        console2.log("canonicalBundle 768 B out, warm callee:", canonicalWarm);
        console2.log("decodeBundleFlat 768 B in, cold callee:", decodeCold);
        console2.log("decodeBundleFlat 768 B in, warm callee:", decodeWarm);
        console2.log("SSTORE zero->nonzero, cold slot:", sstoreCold);
        console2.log("SSTORE nonzero->nonzero, warm slot (same key):", sstoreWarm);
        console2.log("SSTORE state rent of one new commitment slot:", sstoreCold - sstoreWarm);
        console2.log("event 1 topic + 2 words, cold callee:", eventCold);
        console2.log("event 1 topic + 2 words, warm callee:", eventWarm);
        console2.log("one roster EXTSTATICCALL, cold callee:", rosterCold);
        console2.log("one roster EXTSTATICCALL, warm callee:", rosterWarm);
        (uint256 floorLast, uint256 gasAtLast) = _floor();

        console2.log("keccak256 over 768 bytes, in-caller:", gKeccak);
        console2.log("rig floor, empty callee, first bracket:", floorFirst);
        console2.log("rig floor, empty callee, last bracket:", floorLast);
        console2.log("caller gasleft at first bracket:", gasAtFirst);
        console2.log("caller gasleft at last bracket:", gasAtLast);
        // NO net column here, on purpose. The first cut of this test subtracted a floor, and the
        // floor turned out not to be one: the same empty call measured 26,062 / 26,062 / 21,559
        // three times, and a warm logRecord bracket (23,055) came out SMALLER than the empty-call
        // baseline (26,214) — an underflow panic in the rig, not in the bridge. So the components
        // are attributed by differencing whole tests against each other instead, in the D-H block
        // below, where the per-call overhead appears once on each side and cancels without anyone
        // having to know what it is.
        console2.log("floor first / last (NOT subtracted, see the D-H block):", floorFirst);
        console2.log("floor last:", floorLast);
        console2.log("cold-minus-warm on the same SSTORE key (rent, floor cancels):", sstoreCold - sstoreWarm);
        console2.log("cold-minus-warm on canonicalBundle:", canonicalCold - canonicalWarm);
        console2.log("cold-minus-warm on rosterValidator:", rosterCold - rosterWarm);
    }

    /// spec §10 item 16: the lock side, which §6.6 assumed at ~0.3 POL without ever measuring it.
    /// approve is bracketed separately from lockTransfer because the row is the SUM, and a reviewer
    /// has to be able to see which half moved. Both are measured cold and warm, same rule as above.
    function test_lock_and_approve_gas() public {
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        token.mint(address(this), 20 ether);

        bytes memory cdApprove =
            abi.encodeWithSignature("approve(address,uint256)", address(bridge), 7 ether);
        uint256 approveCold = _bracket(address(token), cdApprove, "approve");
        uint256 approveWarm = _bracket(address(token), cdApprove, "approve warm");

        bytes memory cdLock = abi.encodeCall(
            LXONPqcBridgeV1.lockTransfer, (address(token), 3 ether, srcChain, address(0xD000)));
        uint256 lockFirst = _bracket(address(bridge), cdLock, "lockTransfer 1");
        assertEq(bridge.escrowed(address(token)), 3 ether, "the measured lock did not escrow");

        bytes memory cdLock2 = abi.encodeCall(
            LXONPqcBridgeV1.lockTransfer, (address(token), 3 ether, srcChain, address(0xD000)));
        uint256 lockSecond = _bracket(address(bridge), cdLock2, "lockTransfer 2");
        assertEq(bridge.escrowed(address(token)), 6 ether, "the second lock did not escrow");

        console2.log("approve, cold allowance slot:", approveCold);
        console2.log("approve, warm allowance slot:", approveWarm);
        console2.log("lockTransfer, first lock of the lane:", lockFirst);
        console2.log("lockTransfer, second lock of the lane:", lockSecond);
        console2.log("item 16 sum as measured (steady state, approve + lock):", approveWarm + lockSecond);
        console2.log("item 16 sum as measured (cold, approve + lock):", approveCold + lockFirst);
        console2.log("chain id:", destChain, "basefee:", block.basefee);
    }

    /// The byte count every derived figure in §6.3 is arithmetic on, asserted rather than recalled:
    /// 768 B is 4 heads + 2 index arrays + 2 x 186 B signatures, and the tx-intrinsic charge that
    /// fork-gas.sh adds is computed from THIS number, not from the plan's prose.
    function test_bundle_and_claim_calldata_size() public view {
        Fixture memory f = _fixture(1);
        bytes memory defaultCall =
            abi.encodeCall(LXONPqcBridgeV1.claimTransfer, (f.r, BH, f.sigs, new bytes[](0), f.bundle));
        assertEq(f.bundle.length, 768);
        console2.log("claimTransfer calldata bytes incl. selector (default profile):", defaultCall.length);
        console2.log("of which the bundle:", f.bundle.length);
        // The 2,420-byte lattice leg, for the Strong row's byte count. Nothing in the default
        // profile pays for it — the default profile refuses it — so this number is the Strong
        // row's calldata term and nothing more.
        bytes[] memory strong = new bytes[](2);
        strong[0] = new bytes(2420);
        strong[1] = new bytes(2420);
        bytes memory strongCall =
            abi.encodeCall(LXONPqcBridgeV1.claimTransfer, (f.r, BH, f.sigs, strong, f.bundle));
        console2.log("claimTransfer calldata bytes incl. selector (Strong):", strongCall.length);
    }

    /// Rig validation, and the reason the component figures above are printed NET. The first run
    /// of this file reported a logRecord bracket (23,055) SMALLER than its own empty-call floor
    /// (26,214) — an arithmetic underflow, which is the sound a measuring rig makes when the thing
    /// it calls "overhead" is not a constant at all. So the overhead is measured in four pieces
    /// here rather than assumed, and the floor that gets subtracted is the one this prints.
    function test_rig_floor_is_measured_not_assumed() public {
        bytes memory cdEmpty = abi.encodeWithSelector(T7GasProbe.empty.selector);
        bytes memory cdLog = abi.encodeWithSelector(T7GasProbe.logRecord.selector);

        uint256 a0 = gasleft();
        bytes memory cdAgain = abi.encodeWithSelector(T7GasProbe.empty.selector);
        uint256 gEncodeOnly = a0 - gasleft();

        a0 = gasleft();
        (bool ok1, ) = address(probe).call(cdEmpty);
        uint256 gCallOnly = a0 - gasleft();
        require(ok1, "empty call reverted");

        a0 = gasleft();
        (bool ok2, ) = address(probe).call(cdLog);
        uint256 gCallLog = a0 - gasleft();
        require(ok2, "log call reverted");

        a0 = gasleft();
        uint256 b0 = gasleft();
        uint256 gGasleft = a0 - b0;

        assertEq(cdAgain.length, cdEmpty.length, "calldata rebuilt differently");
        console2.log("piece: abi.encodeWithSelector alone:", gEncodeOnly);
        console2.log("piece: call to empty() with cd pre-encoded:", gCallOnly);
        console2.log("piece: call to logRecord() with cd pre-encoded:", gCallLog);
        // Deliberately NOT gCallLog - gCallOnly: the first run underflowed here, because the
        // cold-access baseline can exceed the work being measured. Subtraction only appears below,
        // where it is guarded and where both operands are warm.
        console2.log("piece: gasleft() twice in a row:", gGasleft);
        (uint256 rigFloor, uint256 atFloor) = _floor();
        console2.log("piece: rig floor as _floor() reports it:", rigFloor);
        console2.log("piece: caller gasleft when _floor() ran:", atFloor);

        // The decisive one. If the third figure is not much smaller than the second, the baseline
        // is not a first-touch effect and the brackets are what they say they are; if it is, then
        // every component number above is dominated by cold access and the net column is the only
        // one that means anything. Measured 2026-11-14: empty #1 = 26,056 and logRecord = 23,176,
        // a difference of 2,880 — which is EIP-2929's cold-account access plus a rounding of call
        // overhead, so the second call in this block is expected to be the smaller, honest floor.
        a0 = gasleft();
        (bool ok3, ) = address(probe).call(cdEmpty);
        uint256 gCallEmptyAgain = a0 - gasleft();
        require(ok3, "repeat empty call reverted");
        a0 = gasleft();
        (bool ok4, ) = address(probe).call(cdEmpty);
        uint256 gCallEmptyThird = a0 - gasleft();
        require(ok4, "third empty call reverted");
        console2.log("piece: same empty call, second time:", gCallEmptyAgain);
        console2.log("piece: same empty call, third time:", gCallEmptyThird);
    }

    // ------------------------------------------------------------ A / B / C differential.
    //
    // Three tests that are IDENTICAL except for how many claims they settle, so that the gas each
    // one reports — forge's own per-test figure, the same channel every other number in this repo
    // is read from — differs by exactly the cost of a claim. This is the instrument that does not
    // need a per-call overhead to be constant, which the bracket rig above showed it is not:
    //   claim #1 = B - A,   claim #2 = C - B.
    // The fixtures are built in every variant, in the same order, so the fixture cost cancels too.

    /// A: build both fixtures, settle neither.
    function test_gas_A_no_claims() public {
        Fixture memory f1 = _fixture(1);
        Fixture memory f2 = _fixture(2);
        assertEq(f1.bundle.length, 768);
        assertEq(f2.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
    }

    /// B: the same, plus the first claim.
    function test_gas_B_one_claim() public {
        Fixture memory f1 = _fixture(1);
        Fixture memory f2 = _fixture(2);
        assertEq(f1.bundle.length, 768);
        assertEq(f2.bundle.length, 768);
        _claimGas(f1, "B");
        assertEq(token.balanceOf(recipient), AMOUNT);
    }

    /// C: the same, plus both claims. C-B is the figure the §6.3 row should be quoting, because a
    /// production claim arrives on a lane that has already paid its one-off state rent at least once.
    function test_gas_C_two_claims() public {
        Fixture memory f1 = _fixture(1);
        Fixture memory f2 = _fixture(2);
        assertEq(f1.bundle.length, 768);
        assertEq(f2.bundle.length, 768);
        _claimGas(f1, "C1");
        _claimGas(f2, "C2");
        assertEq(token.balanceOf(recipient), 2 * AMOUNT);
    }

    // ------------------------------------------------------------ D..H: one component each.
    //
    // Each test below is `test_gas_A_no_claims` plus exactly one extra external call, so
    //   component = (that test's reported gas) - (A's reported gas)
    // and the rig's per-call overhead — which the block above proved is not constant — appears on
    // both sides of the subtraction instead of being assumed away. fork-gas.sh does the
    // differencing and prints the table; the arithmetic is out of the contract on purpose, because
    // a figure that needs a comment to be read correctly belongs next to the command that reads it.

    /// The base for D..H: ONE fixture, the same two asserts, and no extra call at all. A builds
    /// two fixtures, which is why the first pass of this block produced component figures SMALLER
    /// than their base — the base was paying for a second _fixture() that D..H never built. Measured
    /// 2026-11-14: D reported 133,968 against A's 177,141. Wrong base, not a negative cost.
    function test_gas_A1_one_fixture_no_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
    }

    /// The caller-side encoding term, isolated. A real transaction does NOT pay this on-chain —
    /// the broadcaster builds the calldata offline — so the claim figures (B-A, C-B) are read as
    /// "test-contract cost of settling one more claim", and subtracting this from them is what
    /// leaves the quantity a chain actually charges. Both columns are printed in RESULTS.md.
    function test_gas_I_encode_only() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        bytes memory cd = abi.encodeCall(
            LXONPqcBridgeV1.claimTransfer, (f.r, BH, f.sigs, new bytes[](0), f.bundle));
        assertEq(cd.length, 1668, "calldata shape moved; recount the intrinsic");
    }

    // ------------------------------------------------------------ K1..K3: the lock side, differed.
    //
    // item 16's row is approve + lockTransfer, and the bracket rig above is the one instrument this
    // file has proved carries an unattributed ~21-27k per call. A lock is ~110-200k, so reading it
    // off a bracket would be a 12-25 % error in the unknown direction. Three tests, each one extra
    // operation over the last:  approve = K1-A1, lock #1 = K2-K1, lock #2 = K3-K2.

    function _approveCalldata() internal view returns (bytes memory) {
        return abi.encodeWithSignature("approve(address,uint256)", address(bridge), 7 ether);
    }

    function _lockCalldata() internal view returns (bytes memory) {
        return abi.encodeCall(LXONPqcBridgeV1.lockTransfer, (address(token), 3 ether, srcChain, address(0xD000)));
    }

    /// K0: the base the K-series is differenced against — route configured and tokens minted, but
    /// no approve and no lock. Skipping this base was the first attempt's error: K1 minus A1 printed
    /// 167,681 for "one approve", because it was really setOutbound + mint + approve. The rule the
    /// file already states twice: a differential needs a base that differs by exactly one thing.
    function test_gas_K0_route_and_mint_only() public {
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        token.mint(address(this), 20 ether);
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(address(this)), 20 ether);
    }

    /// K1: outbound route configured, tokens minted, and ONE approve. No lock.
    function test_gas_K1_approve_only() public {
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        token.mint(address(this), 20 ether);
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(address(this)), 20 ether);
        _bracket(address(token), _approveCalldata(), "K1");
    }

    /// K2: K1 plus the first lock of the lane.
    function test_gas_K2_one_lock() public {
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        token.mint(address(this), 20 ether);
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(address(this)), 20 ether);
        _bracket(address(token), _approveCalldata(), "K2a");
        _bracket(address(bridge), _lockCalldata(), "K2b");
        assertEq(bridge.escrowed(address(token)), 3 ether);
    }

    /// K3: K2 plus a second lock, which is the figure §6.6's per-crossing cost should quote because
    /// production lanes are not virgin state.
    function test_gas_K3_two_locks() public {
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        token.mint(address(this), 20 ether);
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(address(this)), 20 ether);
        _bracket(address(token), _approveCalldata(), "K3a");
        _bracket(address(bridge), _lockCalldata(), "K3b");
        _bracket(address(bridge), _lockCalldata(), "K3c");
        assertEq(bridge.escrowed(address(token)), 6 ether);
    }

    function _nonZero(bytes memory b) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < b.length; ++i) {
            if (b[i] != bytes1(0)) n++;
        }
    }

    /// The subtraction's other half: A1 plus one call to a body that does nothing. Every component
    /// in D..H is then read as (X - J), which removes one identical external call — argument
    /// encoding, dispatcher, call frame, whatever the 26,062 / 21,559 variance turns out to be —
    /// without anyone having to know what it is made of. That is the difference between a
    /// differential and a guess.
    function test_gas_J_empty_call_once() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(probe), abi.encodeWithSelector(T7GasProbe.empty.selector), "J");
    }

    function test_gas_D_canonical_one_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(bridge),
            abi.encodeWithSelector(LXONPqcBridgeV1.canonicalBundle.selector, _asBundle(f)), "D");
    }

    function test_gas_E_decode_one_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(bridge),
            abi.encodeWithSelector(LXONPqcBridgeV1.decodeBundleFlat.selector, f.bundle), "E");
    }

    function test_gas_F_cold_sstore_one_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(probe),
            abi.encodeCall(T7GasProbe.writeCold, (keccak256(f.bundle), bytes32(uint256(0xA9)))), "F");
    }

    function test_gas_G_event_one_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(probe), abi.encodeWithSelector(T7GasProbe.logRecord.selector), "G");
    }

    function test_gas_H_roster_read_one_call() public {
        Fixture memory f = _fixture(1);
        assertEq(f.bundle.length, 768);
        assertEq(token.balanceOf(recipient), 0);
        _bracket(address(registry),
            abi.encodeCall(PqcAlgorithmRegistry.rosterValidator, (uint8(0))), "H");
    }

    /// The intrinsic term, computed from measured bytes rather than from a formula remembered from
    /// the plan: EVM-side figures never include it, and a transaction does. Zero bytes are 4 gas,
    /// non-zero 16 (Cancun), plus the 21,000 base. Printed here so the table in RESULTS.md can add
    /// it without anyone re-counting the calldata by hand.
    function test_tx_intrinsic_from_measured_bytes() public {
        Fixture memory f = _fixture(1);
        bytes memory cd = abi.encodeCall(
            LXONPqcBridgeV1.claimTransfer, (f.r, BH, f.sigs, new bytes[](0), f.bundle));
        uint256 zeros = 0;
        for (uint256 i = 0; i < cd.length; ++i) {
            if (cd[i] == bytes1(0)) zeros++;
        }
        uint256 nonZero = cd.length - zeros;
        uint256 intrinsic = 21000 + zeros * 4 + nonZero * 16;
        // The lock side's census too, so §6.6's per-crossing figure is arithmetic on measured
        // bytes on both legs and not on a remembered 64-byte assumption for an approval.
        bridge.setOutbound(srcChain, address(token), LXONPqcBridgeV1.Mode.Escrow, true);
        bytes memory cdApprove = _approveCalldata();
        bytes memory cdLock = _lockCalldata();
        console2.log("approve calldata bytes:", cdApprove.length, "non-zero:", _nonZero(cdApprove));
        console2.log("lockTransfer calldata bytes:", cdLock.length, "non-zero:", _nonZero(cdLock));

        console2.log("claim calldata bytes:", cd.length);
        console2.log("of which zero bytes:", zeros);
        console2.log("of which non-zero bytes:", nonZero);
        console2.log("tx intrinsic (21000 base + 4/zero + 16/non-zero):", intrinsic);
    }

    /// A Bundle rebuilt from the fixture's own fields, for the public pure call. Kept here rather
    /// than built inside _fixture so the fixture stays exactly the bytes a caller would send.
    function _asBundle(Fixture memory f)
        internal pure
        returns (LXONPqcBridgeV1.Bundle memory b)
    {
        b = LXONPqcBridgeV1.Bundle({
            claimId: f.id, srcBlockHash: BH, rosterIndices: f.idx, mayoSigs: f.mayoSigs
        });
    }
}
