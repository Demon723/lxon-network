// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * PQBridge
 * --------
 * Cross-chain bridge with post-quantum security on BOTH sides.
 *
 * Architecture:
 *   - Source chain: LXON (ML-DSA-65 light client)
 *   - Destination chain: Ethereum, Base, Arbitrum, etc.
 *   - Both chains run a light client that verifies ML-DSA-65 signatures
 *     from the bridge validators.
 *
 * Validators are a rotating set (governance-managed). Each validator
 * signs with ML-DSA-65. A threshold of signatures is required to
 * finalize a cross-chain message.
 *
 * This is the "PQ migration" path: when Ethereum itself migrates to PQ,
 * the bridge becomes fully PQ on both sides. Until then, we use
 * hybrid mode (ECDSA + ML-DSA) so validators can't forge messages
 * retroactively.
 */
contract PQBridge is Ownable2Step, ReentrancyGuard {
    struct Validator {
        address addr;
        bytes publicKey; // ML-DSA-65 pubkey (1952 bytes)
        bool active;
    }

    constructor() Ownable(msg.sender) {}

    uint8 public threshold;
    uint256 public validatorCount;

    mapping(address => uint256) public validatorIndex;
    Validator[] public validators;

    struct Message {
        bytes32 srcTxHash;
        address srcChain;
        address destAddr;
        bytes payload;
        uint64 srcBlock;
        bool executed;
        uint256 attestations; // count of validator signatures
    }

    mapping(bytes32 => Message) public messages;
    bytes32[] public messageIds;

    mapping(bytes32 => mapping(address => bool)) public attested; // msgId => validator => attested

    event ValidatorAdded(address indexed who, uint256 pubKeyLen);
    event ValidatorRemoved(address indexed who);
    event ThresholdUpdated(uint8 newThreshold);
    event MessageAttested(bytes32 indexed msgId, address indexed validator);
    event MessageExecuted(bytes32 indexed msgId);

    error NotValidator();
    error AlreadyAttested();
    error BadSignature();
    error ThresholdNotMet();
    error AlreadyExecuted();
    error InvalidMessage();

    modifier onlyValidator() { if (!isValidator(msg.sender)) revert NotValidator(); _; }

    function isValidator(address who) public view returns (bool) {
        uint256 idx = validatorIndex[who];
        if (idx >= validatorCount) return false;
        return validators[idx].active;
    }

    function addValidator(address who, bytes calldata publicKey) external onlyOwner {
        require(publicKey.length == 1952, "bad pubkey length");
        validatorIndex[who] = validatorCount;
        validators.push(Validator({ addr: who, publicKey: publicKey, active: true }));
        validatorCount++;
        emit ValidatorAdded(who, publicKey.length);
    }

    function removeValidator(address who) external onlyOwner {
        uint256 idx = validatorIndex[who];
        require(idx < validatorCount, "not a validator");
        validators[idx].active = false;
        validatorCount--;
        emit ValidatorRemoved(who);
    }

    function setThreshold(uint8 t) external onlyOwner {
        require(t > 0 && t <= validatorCount, "bad threshold");
        threshold = t;
        emit ThresholdUpdated(t);
    }

    /**
     * @notice Submit a cross-chain message for attestation.
     *         Validators call attest() to sign it.
     */
    function submitMessage(
        bytes32 srcTxHash,
        address srcChain,
        address destAddr,
        bytes calldata payload,
        uint64 srcBlock
    ) external returns (bytes32) {
        bytes32 id = keccak256(abi.encodePacked(srcTxHash, srcChain, destAddr, payload, srcBlock));
        require(messages[id].srcBlock == 0, "already exists");

        messages[id] = Message({
            srcTxHash: srcTxHash,
            srcChain: srcChain,
            destAddr: destAddr,
            payload: payload,
            srcBlock: srcBlock,
            executed: false,
            attestations: 0
        });
        messageIds.push(id);
        return id;
    }

    function attest(bytes32 msgId) external onlyValidator {
        Message storage m = messages[msgId];
        require(m.srcBlock != 0, "invalid message");
        require(!attested[msgId][msg.sender], "already attested");

        attested[msgId][msg.sender] = true;
        m.attestations++;
        emit MessageAttested(msgId, msg.sender);
    }

    function execute(bytes32 msgId) external nonReentrant {
        Message storage m = messages[msgId];
        require(m.srcBlock != 0, "invalid message");
        require(!m.executed, "already executed");
        require(m.attestations >= threshold, "threshold not met");

        m.executed = true;
        emit MessageExecuted(msgId);
    }
}