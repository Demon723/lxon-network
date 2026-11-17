// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * AnchorageAdapter
 * ----------------
 * Anchorage Digital uses MPC-based signing. Their attestations are
 * threshold signatures (t-of-n). On-chain we verify against the group
 * public key using a simple aggregator (in production, use an EIP-4337
 * or BLS aggregator).
 *
 * For v1, we accept a single aggregated signature from their MPC network.
 */
contract AnchorageAdapter is Ownable2Step {
    address public anchorageSigner;
    uint256 public chainId;

    constructor(address _signer, uint256 _chainId) Ownable(msg.sender) {
        anchorageSigner = _signer;
        chainId = _chainId;
    }

    function setSigner(address s) external onlyOwner { anchorageSigner = s; }

    function verifyDeposit(
        bytes32 ref,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external view returns (bool) {
        if (proof.length != 65) return false;

        bytes32 message = keccak256(abi.encodePacked("ANCHORAGE", ref, to, amount, chainId));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(proof.offset)
            s := calldataload(add(proof.offset, 32))
            v := byte(0, calldataload(add(proof.offset, 64)))
        }

        address recovered = ecrecover(ethHash, v, r, s);
        return recovered == anchorageSigner;
    }
}