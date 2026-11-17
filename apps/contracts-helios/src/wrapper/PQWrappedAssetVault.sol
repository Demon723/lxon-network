// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface ICustodianAdapter {
    function verifyDeposit(
        bytes32 ref,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external view returns (bool);
}

/**
 * PQWrappedAssetVault
 * -------------------
 * Routes custodian attestations to PQWrappedAsset contracts.
 *
 * Real-world flow:
 *   1. User sends BTC to a custody address (BitGo, Anchorage, etc.)
 *   2. Custodian detects deposit and produces a signed attestation
 *   3. Relayer submits attestation to this vault
 *   4. Vault verifies via custodian's adapter, then calls attestNative()
 *
 * The adapter is per-custodian and encodes that custodian's signature scheme.
 */
contract PQWrappedAssetVault is Ownable2Step {
    using SafeERC20 for IERC20;

    struct Attestation {
        address custodianAdapter;
        bytes32 ref;
        address to;
        uint256 amount;
        bytes32 assetId;      // keccak256("BTC" | "ETH" | ...)
        uint256 submittedAt;
        bool processed;
    }

    mapping(bytes32 => Attestation) public attestations;   // ref => Attestation
    mapping(address => bool) public relayers;
    mapping(bytes32 => address) public wrappedAssets;       // assetId => wrapped contract

    event WrappedAssetRegistered(bytes32 indexed assetId, address wrapped);
    event AttestationSubmitted(bytes32 indexed ref, address indexed to, uint256 amount);
    event AttestationProcessed(bytes32 indexed ref);
    event RelayerSet(address indexed who, bool allowed);

    error NotRelayer();
    error AlreadyProcessed();
    error InvalidProof();
    error AssetNotRegistered();

    modifier onlyRelayer() { if (!relayers[msg.sender] && msg.sender != owner()) revert NotRelayer(); _; }

    constructor() Ownable(msg.sender) {}

    function setRelayer(address who, bool allowed) external onlyOwner {
        relayers[who] = allowed;
        emit RelayerSet(who, allowed);
    }

    function registerWrappedAsset(bytes32 assetId, address wrapped) external onlyOwner {
        wrappedAssets[assetId] = wrapped;
        emit WrappedAssetRegistered(assetId, wrapped);
    }

    /**
     * @notice Submit and verify an attestation in one call.
     */
    function submitAttestation(
        bytes32 ref,
        bytes32 assetId,
        address custodianAdapter,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external onlyRelayer {
        if (attestations[ref].submittedAt != 0) revert AlreadyProcessed();

        address wrapped = wrappedAssets[assetId];
        if (wrapped == address(0)) revert AssetNotRegistered();

        // Verify via the custodian's adapter
        bool ok = ICustodianAdapter(custodianAdapter).verifyDeposit(ref, to, amount, proof);
        if (!ok) revert InvalidProof();

        attestations[ref] = Attestation({
            custodianAdapter: custodianAdapter,
            ref: ref,
            to: to,
            amount: amount,
            assetId: assetId,
            submittedAt: block.timestamp,
            processed: false
        });
        emit AttestationSubmitted(ref, to, amount);

        // Mint wrapped
        PQWrappedAssetLike(wrapped).attestNative(to, amount, ref);
        attestations[ref].processed = true;
        emit AttestationProcessed(ref);
    }
}

interface PQWrappedAssetLike {
    function attestNative(address to, uint256 amount, bytes32 ref) external;
}
