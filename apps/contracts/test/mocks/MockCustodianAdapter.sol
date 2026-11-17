// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Mock custodian adapter for testing.
 */
contract MockCustodianAdapter {
    function verifyDeposit(
        bytes32 ref,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external pure returns (bool) {
        // Always return true for testing
        return true;
    }
}