// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PqcBridgeHarness} from "./PqcBridgeHarness.sol";

/// EIP-170. Not a formality for this contract: DELTA-C6-4 lands it closer to the ceiling than any
/// earlier task, and the copy it is built from (v4.1, blob e305af57) was never measured against
/// the ceiling at all because it had no bundle path. Measured numbers, the build settings that
/// produced them, and the headroom trend are recorded in the Plan 2 ledger row for Task 7 — they
/// are deliberately NOT asserted here, because a test that pins a size figure has to be edited
/// every time anything else is added, and an assertion that is routinely edited to pass is an
/// assertion that no longer means anything.
///
/// What IS asserted is the property that decides whether this contract can be deployed at all,
/// read from the code that actually landed rather than from a build log.
contract PqcBridgeSizeTest is PqcBridgeHarness {
    function test_bridge_runtime_code_fits_eip170() public view {
        uint256 n = address(bridge).code.length;
        assertLe(n, 24576, "LXONPqcBridgeV1 exceeds the EIP-170 runtime cap and cannot deploy");
        // The registry is the other half of the pair, and it is what Plan 5 will grow.
        assertLe(address(registry).code.length, 24576, "PqcAlgorithmRegistry exceeds the cap");
    }

    /// The copy is still recognisably v4.1-sized plus the deltas: a runtime that SHRANK by
    /// thousands of bytes would mean something in the claim path stopped existing, and the
    /// invariant suite compares sources, not compiled size. Lower bound only — the upper bound is
    /// the test above, which is the one that can fail.
    function test_bridge_is_not_accidentally_a_stub() public view {
        assertGe(address(bridge).code.length, 20000,
            "the bridge got smaller than its v4.1 body; check the delta blocks were not deleted");
    }
}
