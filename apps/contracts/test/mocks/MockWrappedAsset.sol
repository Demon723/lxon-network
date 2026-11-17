// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Mock wrapped asset for testing.
 */
contract MockWrappedAsset {
    function attestNative(address to, uint256 amount, bytes32 ref) external {
        // Mock implementation - just emit an event or do nothing
    }
}