// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * AuditTrail
 * ----------
 * Immutable log of compliance-relevant events. Append-only; no deletion.
 * Anchors periodic Merkle roots to LXON for external audit.
 */
contract AuditTrail {
    struct Entry {
        uint64  timestamp;
        address actor;
        bytes32 kind;         // keccak256("WRAP"|"UNWRAP"|"KYC_UPDATE"|...)
        bytes32 subject;      // who the event concerns
        bytes32 dataHash;     // keccak256 of off-chain details
    }

    Entry[] public entries;
    bytes32 public latestRoot;

    event Logged(uint256 indexed index, bytes32 kind, address indexed actor, bytes32 subject);

    function log(bytes32 kind, address subject, bytes32 dataHash) external returns (uint256) {
        entries.push(Entry({ timestamp: uint64(block.timestamp), actor: msg.sender, kind: kind, subject: bytes32(uint256(uint160(subject))), dataHash: dataHash }));
        emit Logged(entries.length - 1, kind, msg.sender, bytes32(uint256(uint160(subject))));
        return entries.length - 1;
    }

    function count() external view returns (uint256) { return entries.length; }

    function anchorRoot(bytes32 root) external { latestRoot = root; }
}
