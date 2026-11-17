// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * SealcoinREST
 * -----------
 * Client for the SEALCOIN REST API.
 *
 * SEALCOIN is the data-availability fee token used to pay for satellite
 * telemetry anchoring. This contract is a thin wrapper that delegates
 * the actual HTTP call to a trusted relayer (the gateway operator).
 *
 * The relayer is permissioned by governance; anyone can submit a signed
 * relay request, but only the relayer's signature is accepted.
 */
contract SealcoinREST {
    address public relayer;
    address public governor;

    mapping(bytes32 => bool) public usedNonces;

    event Relay(bytes32 indexed requestId, address indexed token, uint256 amount);
    event RelayerUpdated(address indexed from, address indexed to);

    error Unauthorized();
    error BadSignature();
    error AlreadyUsed();
    error InsufficientBalance();

    struct RelayReq {
        address token;
        uint256 amount;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    constructor(address _relayer, address _gov) {
        relayer = _relayer;
        governor = _gov;
    }

    modifier onlyGovernor() { if (msg.sender != governor) revert Unauthorized(); _; }

    function setRelayer(address r) external onlyGovernor {
        emit RelayerUpdated(relayer, r);
        relayer = r;
    }

    /**
     * Submit a signed relay request to pay SEALCOIN fees.
     * The relayer batches these and submits them to the REST endpoint.
     */
    function relay(RelayReq calldata req) external {
        if (req.deadline < block.timestamp) revert BadSignature();
        bytes32 digest = keccak256(
            abi.encodePacked(req.token, req.amount, req.deadline, req.nonce)
        );
        if (usedNonces[keccak256(abi.encodePacked(req.nonce, msg.sender))]) revert AlreadyUsed();
        if (req.signature.length != 65) revert BadSignature();
        bytes memory sigCopy = req.signature;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sigCopy, 0x20))
            s := mload(add(sigCopy, 0x40))
            v := byte(0, mload(add(sigCopy, 0x60)))
        }
        if (v != 27 && v != 28) v = v + 27;
        if (ecrecover(digest, v, r, s) != relayer) revert BadSignature();

        usedNonces[keccak256(abi.encodePacked(req.nonce, msg.sender))] = true;
        emit Relay(digest, req.token, req.amount);
    }
}