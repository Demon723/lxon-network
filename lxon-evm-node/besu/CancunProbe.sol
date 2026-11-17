// SPDX-License-Identifier: MIT
// Throwaway Cancun-opcode probe. Proves TSTORE/TLOAD (EIP-1153) and MCOPY (EIP-5656)
// actually execute on the target chain, not just that the compiler emitted them.
pragma solidity ^0.8.26;

contract CancunProbe {
    // TSTORE 0x5c + TLOAD 0x5d. The transient round-trip is also mirrored into slot 0
    // so a committed transaction proves the write path end-to-end.
    function transientRoundTrip(uint256 v) external returns (uint256 got) {
        assembly {
            tstore(0x00, v)
            got := tload(0x00)
            sstore(0x00, got)
        }
    }

    // MCOPY 0x5e: move 64 bytes inside memory, then read the destination back.
    function mcopyRoundTrip(uint256 a, uint256 b) external pure returns (uint256 x, uint256 y) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            mcopy(0x40, 0x00, 0x40)
            x := mload(0x40)
            y := mload(0x60)
        }
    }

    // Read the transient slot written by transientRoundTrip: tload must survive within
    // the same transaction, and only within it.
    function readTransient() external view returns (uint256) {
        uint256 v;
        assembly {
            v := tload(0x00)
        }
        return v;
    }
}
