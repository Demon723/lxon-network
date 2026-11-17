// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ValidatorKeyRegistry — Simple validator key management.
 *
 * Each validator can register a public key for consensus participation.
 * Key rotation is supported for security.
 */
contract ValidatorKeyRegistry {
    struct KeyRecord {
        bytes32 pubKeyHash;
        uint64  activatedAt;
        bool    revoked;
    }

    address public governance;
    mapping(address => KeyRecord) public activeKey;
    mapping(address => bytes32[]) public pendingRotation;
    mapping(bytes32 => bool) public revoked;
    mapping(address => bool) public compromisedValidator;

    event KeyRotated(address indexed validator, bytes32 oldHash, bytes32 newHash);
    event RotationProposed(address indexed validator, bytes32 newHash);
    event KeyRevoked(bytes32 indexed pubKeyHash, address indexed validator);
    event ValidatorFlaggedCompromised(address indexed validator, bool flagged);

    error NotGovernance();
    error NoPending();
    error AlreadyRevoked();

    modifier onlyGovernance() { if (msg.sender != governance) revert NotGovernance(); _; }

    constructor(address g) { governance = g; }

    function setGovernance(address g) external onlyGovernance { governance = g; }

    function proposeRotation(bytes32 newHash) external {
        pendingRotation[msg.sender].push(newHash);
        emit RotationProposed(msg.sender, newHash);
    }

    function acceptRotation() external {
        bytes32[] storage p = pendingRotation[msg.sender];
        if (p.length == 0) revert NoPending();
        bytes32 h = p[p.length - 1];
        delete pendingRotation[msg.sender];
        bytes32 old = activeKey[msg.sender].pubKeyHash;
        activeKey[msg.sender].pubKeyHash = h;
        activeKey[msg.sender].activatedAt = uint64(block.timestamp);
        emit KeyRotated(msg.sender, old, h);
    }

    function flagCompromised(address v, bool f) external onlyGovernance {
        compromisedValidator[v] = f;
        emit ValidatorFlaggedCompromised(v, f);
    }

    function forceRotate(address v, bytes32 newHash) external onlyGovernance {
        bytes32 old = activeKey[v].pubKeyHash;
        if (old != 0) { revoked[old] = true; emit KeyRevoked(old, v); }
        activeKey[v].pubKeyHash = newHash;
        activeKey[v].activatedAt = uint64(block.timestamp);
        emit KeyRotated(v, old, newHash);
    }

    function isAuthorized(address v, bytes32 h) external view returns (bool) {
        if (revoked[h]) return false;
        return activeKey[v].pubKeyHash == h;
    }

    function revokeKey(bytes32 h) external onlyGovernance {
        if (revoked[h]) revert AlreadyRevoked();
        revoked[h] = true;
        emit KeyRevoked(h, address(0));
    }
}
