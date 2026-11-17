// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LXONPqcBridgeV1} from "../../src/pqc/LXONPqcBridgeV1.sol";
import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";
import {LXONTestToken} from "./LXONTestToken.sol";

/// Three attester EOAs with keys the test itself prints. These are throwaway
/// signing accounts created by `makeAddr`-style derivation inside the EVM test
/// process; no keystore is read, no real chain is contacted, and nothing here is
/// key material in any sense that matters.
struct Attester {
    address addr;
    uint256 key;
}

abstract contract PqcBridgeHarness is Test {
    LXONPqcBridgeV1 internal bridge;
    PqcAlgorithmRegistry internal registry;
    LXONTestToken internal token;
    Attester internal a1;
    Attester internal a2;
    Attester internal a3;
    // The plan wrote address(0xTime), which is not a hex literal — solc refuses it with
    // "Hexadecimal digit missing or invalid" (measured). 0x715E is the same joke in digits
    // solc accepts; the value only has to be a non-zero address that no test holds keys for.
    address internal constant TIMETIME = address(0x715E);
    /// The payout recipient every fixture Request uses. A storage-style constant in the
    /// harness so Tasks 5-8 name it once; it is not the bridge and not address(0), which
    /// are the two values _validatedInbound refuses.
    address internal recipient = address(0xC0DE);
    uint256 internal constant DEST_CHAIN = 137;
    uint256 internal constant SRC_CHAIN = 724;

    /// A fourth account that is deliberately NOT in the validator set — the cheap way
    /// to reach the admissibility guard (see test_inadmissible_signer_reverts).
    uint256 internal constant OUTSIDER_KEY = 0xFFFF;

    function _mk(uint256 seed) internal returns (Attester memory a) {
        a.key = seed;
        a.addr = vm.addr(seed);
    }

    /// `public virtual`, not `internal`: forge-std's Test already declares
    /// `function setUp() public virtual`, and an `internal setUp()` in the harness is three
    /// compiler errors (missing override specifier, overriding a non-virtual function,
    /// visibility differs) rather than a design choice. Derived suites call super.setUp()
    /// and then add their own route wiring.
    function setUp() public virtual {
        // The copied bridge asserts _r.destChainId == block.chainid on every claim, and anvil
        // starts at 31337, so the chain the plan's Requests name has to be set before any of
        // them is claimed. Done first so nothing deployed in between can observe a different id.
        vm.chainId(DEST_CHAIN);
        a1 = _mk(0xA11CE);
        a2 = _mk(0xB0b);
        a3 = _mk(0xC0FFEE);
        vm.warp(1_700_000_000);
        token = new LXONTestToken();
        address[] memory set = new address[](3);
        set[0] = a1.addr; set[1] = a2.addr; set[2] = a3.addr;
        // The registry is real, not a mock: the binding check reads the roster through it, so a
        // stub would let Task 6's central property pass on a fixture instead of on the code.
        registry = new PqcAlgorithmRegistry(address(this), address(0x9A15E));
        // minStake 0 with stakeToken address(0) is the Polygon-side shape v4.1 documents at
        // :79-80; it is also what makes isAdmissible reduce to "is in the set" here.
        bridge = new LXONPqcBridgeV1(address(0), 0, TIMETIME, set, 2, 1 ether, 1e24,
            _registryHandleFor(address(registry)));
        // attester i is roster index i, with a MAYO public key at the ruled length.
        registry.setRosterKey(0, a1.addr, _rosterKey(0x11), 1);
        registry.setRosterKey(1, a2.addr, _rosterKey(0x22), 1);
        registry.setRosterKey(2, a3.addr, _rosterKey(0x33), 1);
        token.setBridge(address(bridge));
        vm.label(a1.addr, "attester1");
        vm.label(a2.addr, "attester2");
        vm.label(a3.addr, "attester3");
    }

    /// The registry handle the bridge is constructed with. The handle is `immutable`, so
    /// construction is the only moment a suite can choose it, and this hook is the only way to do
    /// that without duplicating the whole fixture (and with it, the wiring and the token's bridge
    /// pointer). The default is the real registry, which is what every suite so far needs. Task 7's
    /// mock suites return a wrapper AROUND it — never a replacement — because the roster the
    /// same-party binding reads has to stay the real roster.
    function _registryHandleFor(address realRegistry) internal virtual returns (address) {
        return realRegistry;
    }

    /// A Request exactly as lockTransfer would produce it. The parameter is `_to`, not
    /// `recipient`: the harness has a storage field of that name and solc warns on the shadow —
    /// and a future edit inside this function that meant the field would silently get the caller's
    /// argument instead, which is the same value today only because every caller passes it.
    function _request(uint256 nonce, uint256 total, uint256 amount, address _to)
        internal view returns (LXONPqcBridgeV1.Request memory r)
    {
        r = LXONPqcBridgeV1.Request({
            srcChainId: SRC_CHAIN,
            srcBridge: address(0xBEEF),
            destBridge: address(bridge),
            destChainId: DEST_CHAIN,
            laneNonce: nonce,
            srcTotalSent: total,
            srcToken: address(token),
            amount: amount,
            sender: address(0xD000),
            recipient: _to,
            srcBlock: 1_000
        });
    }

    /// ECDSA signatures over claimDigest, strictly ascending by recovered signer,
    /// which is what v4.1:396 demands and what makes a canonical bundle producible.
    function _signQuorum(bytes32 id, bytes32 srcBlockHash, uint256[] memory keys)
        internal view returns (bytes[] memory sigs)
    {
        bytes32 digest = bridge.claimDigest(id, srcBlockHash);
        sigs = new bytes[](keys.length);
        address[] memory signers = new address[](keys.length);
        for (uint256 i = 0; i < keys.length; ++i) signers[i] = vm.addr(keys[i]);
        // sort ascending by address
        for (uint256 i = 0; i < keys.length; ++i) {
            for (uint256 j = i + 1; j < keys.length; ++j) {
                if (signers[j] < signers[i]) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (keys[i], keys[j]) = (keys[j], keys[i]);
                }
            }
        }
        for (uint256 i = 0; i < keys.length; ++i) sigs[i] = _sign(keys[i], digest);
    }

    /// The same bundle with the order deliberately inverted: v4.1 requires strictly
    /// ascending recovered signers, and a bundle that is valid-but-descending is the
    /// input that check exists to refuse.
    function _signQuorumDescending(bytes32 id, bytes32 srcBlockHash)
        internal view returns (bytes[] memory sigs)
    {
        bytes[] memory up = _signQuorum(id, srcBlockHash, _twoKeys());
        require(up.length == 2, "descending helper assumes a two-signature bundle");
        sigs = new bytes[](2);
        sigs[0] = up[1];
        sigs[1] = up[0];
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _twoKeys() internal view returns (uint256[] memory k) {
        k = new uint256[](2);
        k[0] = a1.key;
        k[1] = a2.key;
    }

    function _oneKey() internal view returns (uint256[] memory k) {
        k = new uint256[](1);
        k[0] = a1.key;
    }

    /// Two keys where one signer is an outsider: the quorum is well-formed and
    /// ascending, so the only thing left to refuse it is the admissibility guard.
    function _twoKeysIncludingOutsider() internal view returns (uint256[] memory k) {
        k = new uint256[](2);
        k[0] = a1.key;
        k[1] = OUTSIDER_KEY;
    }

    /// The seam Tasks 5-7 replace. Today it is v4.1's three-argument claimTransfer;
    /// Task 5 changes ONLY this body to the five-argument bundle call, so every
    /// inherited-rule test in PqcBridgeBase.t.sol keeps running unchanged across the
    /// copy's first delta. That is the point: the rules are pinned before the new
    /// behaviour exists, which is what makes a later regression visible as a delta.
    /// v4.1's three-argument form is gone, so the inherited-rule tests reach the claim
    /// path through here. They get a canonical bundle built from their own request,
    /// which keeps every one of them asserting what it always asserted — and it is only
    /// possible because Task 6 has not landed, so the bundle's roster indices are not yet
    /// checked against the recovered signers. That caveat lives where it can be seen:
    /// above _canonicalBundleFor.
    function _claim(LXONPqcBridgeV1.Request memory r, bytes32 bh, bytes[] memory sigs) internal {
        _claimFull(r, bh, sigs, new bytes[](0), _canonicalBundleFor(r, bh));
    }

    /// Task 5's real entry point, kept as a separate helper so the inherited-rule tests
    /// can keep calling the three-line `_claim` above while the bundle surface lands.
    function _claimFull(
        LXONPqcBridgeV1.Request memory r,
        bytes32 bh,
        bytes[] memory sigs,
        bytes[] memory mldsaSigs,
        bytes memory bundle
    ) internal {
        bridge.claimTransfer(r, bh, sigs, mldsaSigs, bundle);
    }

    /// A Mint route on the source chain, bound to the harness token, ready to claim.
    function _configureMintInbound(uint256 cap) internal {
        bridge.setPeer(SRC_CHAIN, address(0xBEEF));
        bridge.setInbound(SRC_CHAIN, address(token), address(token), LXONPqcBridgeV1.Payout.Mint, cap, true);
    }

    /// The fixture the bundle and later bridge suites configure from setUp(). The name in
    /// the plan says "AndLock"; nothing here locks, because a Payout.Mint route pays by
    /// minting and needs no escrow — the lock that DOES matter is in
    /// test_release_payout_short_escrow_reverts, where it is the point of the case.
    function _configureInboundAndLock() internal {
        _configureMintInbound(10 ether);
    }

    // One MAYO signature at the ruled revision's length: 186 bytes at
    // MAYO-C commit 4108b71d (T2 row 23). Never 239 — that number is the pre-correction
    // reading and spec §0 decision 15 outranks it.
    // (Plain // and not ///: solc parses a leading @ as a NatSpec tag, and the hash in the
    //  prose made it a documentation error on the function below.)
    function _mayoStub(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(186);
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }

    /// ML-DSA-44 signatures for the Strong profile's lattice leg: 2,420 bytes each, the length
    /// the registry's own paramHash names ("mldsa44/1312/2560/2420"). Nothing here checks that
    /// length and the bridge deliberately does not either — the verifier (Plan 5's C5) owns
    /// scheme-level validity; Plan 2 only owns asking for one signature per quorum member and
    /// refusing when the dependency it would verify against is absent.
    function _mldsaStub(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(2420);
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }

    /// `n` lattice signatures, so a case can name the count it wants refused: _mldsa(1) is the
    /// short bundle, _mldsa(3) the over-long one, _mldsa(threshold) the only accepted shape.
    function _mldsa(uint256 n) internal pure returns (bytes[] memory s) {
        s = new bytes[](n);
        for (uint256 i = 0; i < n; ++i) s[i] = _mldsaStub(uint8(0xA0 + i));
    }

    /// Roster indices {0,1}: the attesters _twoKeys() signs with. Derived from the roster
    /// rather than recalled -- see _indicesForKeys.
    function _rosterKey(uint8 fill) internal pure returns (bytes memory b) {
        b = new bytes(4912);                       // MAYO_PK_BYTES, the ruled revision
        for (uint256 i = 0; i < b.length; ++i) b[i] = bytes1(fill);
    }
    function _two() internal pure returns (uint8[] memory k) {
        k = new uint8[](2);
        k[0] = 0;
        k[1] = 1;
    }

    function _two186() internal pure returns (bytes[] memory s) {
        s = new bytes[](2);
        s[0] = _mayoStub(0x11);
        s[1] = _mayoStub(0x22);
    }

    /// The indices that honestly describe a set of signing keys, read back out of the
    /// roster through the same direction the contract uses. Task 6 removed the recorded
    /// lie (indices {0,1} were claimed without any check that they named the signers): with
    /// the binding live, such a bundle is refused, so the harness has to look up what it is
    /// claiming. Task 6 Step 4 greps for the marker word to prove the seam is honest now.
    function _indicesForKeys(uint256[] memory keys) internal view returns (uint8[] memory idx) {
        idx = new uint8[](keys.length);
        for (uint256 i = 0; i < keys.length; ++i) {
            int256 got = registry.rosterIndexOf(vm.addr(keys[i]));
            require(got >= 0, "harness signed with a key that is not rostered");
            idx[i] = uint8(uint256(got));
        }
    }

    /// Flat-encoded, exactly the form the contract accepts; see PqcSchemeWord's sibling
    /// note in the bridge. A base test failing on "bundle not canonical" means this has
    /// drifted toward abi.encode(struct) — fix the helper, never the assertion.
    function _flatBundle(bytes32 id, bytes32 blockHash, uint8[] memory idx, bytes[] memory mayoSigs)
        internal pure returns (bytes memory)
    {
        return abi.encode(id, blockHash, idx, mayoSigs);
    }

    /// The honest default: bundle for the request, signed by _twoKeys() (attesters 1 and 2),
    /// with the indices those keys actually hold in the roster.
    function _canonicalBundleFor(LXONPqcBridgeV1.Request memory r, bytes32 bh)
        internal view returns (bytes memory)
    {
        uint256[] memory keys = _twoKeys();
        return _flatBundle(bridge.computeClaimId(r), bh, _indicesForKeys(keys), _two186());
    }
}
