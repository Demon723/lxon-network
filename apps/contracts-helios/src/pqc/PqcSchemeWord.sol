// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// `unpack` lives in a library rather than as a registry member because the bridge
/// must decode the packed word without a second EXTSTATICCALL: a `public pure`
/// function on the registry is not callable statically from another contract's
/// `view` without paying for the call, and the registry's whole claim-time price is
/// already one call. Both sides import this file; neither redefines the layout.
///
/// Bit layout, stated once for the whole PQC surface:
///   [0]      present
///   [1]      enabled
///   [2..3]   venue (uint8)
///   [4]      authorising, DERIVED from the mode at read time, never stored
///   [5..12]  minSecurityLevel
library PqcSchemeWord {
    uint256 internal constant FLAG_PRESENT = 1;
    uint256 internal constant FLAG_ENABLED = 2;
    uint256 internal constant FLAG_AUTHORISING = 16;

    function pack(bool present, bool enabled, uint8 venue, bool authorising, uint8 level)
        internal pure returns (uint256)
    {
        return (present ? FLAG_PRESENT : 0)
            | (enabled ? FLAG_ENABLED : 0)
            | (uint256(venue) << 2)
            | (authorising ? FLAG_AUTHORISING : 0)
            | (uint256(level) << 5);
    }

    function unpack(uint256 w)
        internal pure returns (bool present, bool enabled, uint8 venue, bool authorising, uint8 level)
    {
        present = w & FLAG_PRESENT == FLAG_PRESENT;
        enabled = w & FLAG_ENABLED == FLAG_ENABLED;
        venue = uint8((w >> 2) & 3);
        authorising = w & FLAG_AUTHORISING == FLAG_AUTHORISING;
        level = uint8(w >> 5);
    }
}
