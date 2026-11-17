// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PqcAlgorithmRegistry} from "../../src/pqc/PqcAlgorithmRegistry.sol";

/// Stands in for the two registry shapes a real one cannot produce, so the bridge's refusal to
/// guess at them can actually be exercised:
///
///   (1) a mode word outside {0, 1} — the Task 2 registry can only ever answer Default or Strong,
///       so "what does the bridge do with 2?" has no input without a mock; and
///   (2) a packed row whose authorising bit disagrees with the mode. In this build the bit is
///       DERIVED from `_mode` inside `readScheme`, so the two can never disagree — which is
///       precisely why the bridge must not rely on that. The day the mode and the row live in
///       different contracts (or a later revision stores the bit), a derived bit becomes a
///       remembered one, and the only thing standing between Strong mode and a skipped
///       verification is the require this fixture lets us test.
///
/// Everything else forwards to the real registry. That is deliberate: the roster the same-party
/// binding reads has to be the one Task 3 built, or the test passes on a fixture instead of on
/// the code.
///
/// `verifyMode` is `view` because the bridge's read is a STATICCALL. A mock that counted calls in
/// storage would revert under static context and turn every "read once" assertion into a pass on
/// a broken fixture. Call counts therefore come from `vm.expectCall(..., count)` in the test,
/// which observes the real call and needs no cooperation from the callee.
contract MockRegistry {
    PqcAlgorithmRegistry public immutable inner;

    uint256 public mode;
    bool private _rowOverridden;
    uint256 private _rowWord;

    constructor(address innerRegistry) {
        inner = PqcAlgorithmRegistry(innerRegistry);
    }

    /// 0 = Default, 1 = Strong, anything else is the lie under test.
    function setMode(uint256 m) external {
        mode = m;
    }

    /// Answer this word for every readScheme, whatever id. The test passes a word taken from a
    /// real row (mayo2's: present, enabled, Offchain, NOT authorising) rather than hand-packing
    /// bits, so the fixture cannot drift from PqcSchemeWord's layout unnoticed.
    function setRowWord(uint256 packed) external {
        _rowOverridden = true;
        _rowWord = packed;
    }

    function verifyMode() external view returns (uint256) {
        return mode;
    }

    function readScheme(bytes32 id) external view returns (uint256) {
        return _rowOverridden ? _rowWord : inner.readScheme(id);
    }

    function readVerifier(bytes32 id) external view returns (address) {
        return inner.readVerifier(id);
    }

    function rosterValidator(uint8 index) external view returns (address) {
        return inner.rosterValidator(index);
    }

    function rosterIndexOf(address validator) external view returns (int256) {
        return inner.rosterIndexOf(validator);
    }

    function mldsaBlobFor(uint8 index) external view returns (address) {
        return inner.mldsaBlobFor(index);
    }
}
