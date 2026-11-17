// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {MlDsaVerifierFactory} from "./pq/MlDsaVerifierFactory.sol";

/**
 * SatelliteSignatureV2
 * --------------------
 * On-chain PQ verification of satellite telemetry.
 *
 * Unlike V1 (which used M-of-N attestors because Solidity couldn't verify
 * ML-DSA), V2 verifies the satellite's ML-DSA-65 signature directly on-chain
 * using MlDsaVerifierFactory.
 *
 * Storage layout:
 *   - satelliteId => (publicKey, highestSeq)
 *   - anchorId    => (satelliteId, payloadHash, seq, emittedAt, verifiedAt)
 *
 * Verification is expensive (~5–8M gas), so the gateway batches anchors
 * per satellite and submits one tx per batch.
 */
contract SatelliteSignatureV2 {
    struct Satellite {
        bytes publicKey;    // ML-DSA-65 pubkey (1952 bytes)
        uint64 highestSeq;
        bool registered;
    }

    struct Anchor {
        bytes32 satelliteId;
        bytes32 payloadHash;
        uint64 seq;
        uint64 emittedAt;
        uint64 verifiedAt;
    }

    MlDsaVerifierFactory public immutable verifierFactory;
    address public governance;
    uint256 public anchorFee = 0.001 ether;

    mapping(bytes32 => Satellite) public satellites;   // satId => Satellite
    mapping(bytes32 => Anchor) public anchors;         // anchorId => Anchor
    bytes32[] public anchorIds;

    event SatelliteRegistered(bytes32 indexed satId, uint256 pubKeyLen);
    event AnchorVerified(bytes32 indexed anchorId, bytes32 indexed satId, bytes32 payloadHash, uint64 seq);
    event GovernanceTransferred(address indexed from, address indexed to);
    event FeeUpdated(uint256 newFee);

    error NotGovernance();
    error NotRegistered();
    error StaleSequence();
    error BadSignature();
    error InsufficientFee();

    modifier onlyGovernance() { if (msg.sender != governance) revert NotGovernance(); _; }

    constructor(address _gov) {
        governance = _gov;
        verifierFactory = new MlDsaVerifierFactory();
    }

    function setGovernance(address g) external onlyGovernance {
        emit GovernanceTransferred(governance, g);
        governance = g;
    }

    function setAnchorFee(uint256 f) external onlyGovernance {
        anchorFee = f;
        emit FeeUpdated(f);
    }

    /**
     * Register a satellite's ML-DSA-65 public key.
     * Governance-only because this is the trust root for that satellite.
     */
    function registerSatellite(bytes32 satId, bytes calldata publicKey) external onlyGovernance {
        require(publicKey.length == 1952, "bad pubkey length");
        satellites[satId] = Satellite({ publicKey: publicKey, highestSeq: 0, registered: true });
        emit SatelliteRegistered(satId, publicKey.length);
    }

    /**
     * Anchor a PQ-signed telemetry packet.
     *
     * Message construction (must match satellite-side):
     *   message = satId || seq || emittedAt || payloadHash
     *
     * @param payload   The raw telemetry payload
     * @param signature ML-DSA-65 signature over the canonical message
     */
    function anchor(
        bytes32 satelliteId,
        bytes calldata payload,
        bytes calldata signature,
        uint64 seq,
        uint64 emittedAt
    ) external payable returns (bytes32) {
        Satellite storage s = satellites[satelliteId];
        if (!s.registered) revert NotRegistered();
        if (seq <= s.highestSeq) revert StaleSequence();
        if (msg.value < anchorFee) revert InsufficientFee();

        bytes32 payloadHash = keccak256(payload);
        bytes32 anchorId = keccak256(abi.encodePacked(satelliteId, payloadHash, seq));

        // Canonical message
        bytes memory message = abi.encodePacked(satelliteId, seq, emittedAt, payloadHash);

        // On-chain PQ verification
        bool ok = verifierFactory.verify(s.publicKey, message, signature);
        if (!ok) revert BadSignature();

        anchors[anchorId] = Anchor({
            satelliteId: satelliteId,
            payloadHash: payloadHash,
            seq: seq,
            emittedAt: emittedAt,
            verifiedAt: uint64(block.timestamp)
        });
        anchorIds.push(anchorId);
        s.highestSeq = seq;

        emit AnchorVerified(anchorId, satelliteId, payloadHash, seq);
        return anchorId;
    }

    function anchorCount() external view returns (uint256) { return anchorIds.length; }
    function getAnchorIds() external view returns (bytes32[] memory) { return anchorIds; }
}
