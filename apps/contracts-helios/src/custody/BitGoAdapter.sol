// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * BitGoAdapter
 * ------------
 * Verifies BitGo deposit attestations. BitGo signs deposits with an
 * ECDSA key controlled by their custody infrastructure. When BitGo adds
 * ML-DSA signing (announced for Q3 2026), we can swap to hybrid mode.
 *
 * Attestation format (bytes):
 *   [0..32)   r
 *   [32..64)  s
 *   [64]      v
 *
 * In production, use EIP-712 structured signing.
 */
contract BitGoAdapter is Ownable2Step {
    address public bitgoSigner;
    uint256 public chainId;

    event SignerUpdated(address indexed newSigner);

    constructor(address _signer, uint256 _chainId) Ownable(msg.sender) {
        bitgoSigner = _signer;
        chainId = _chainId;
    }

    function setSigner(address s) external onlyOwner { bitgoSigner = s; emit SignerUpdated(s); }

    function verifyDeposit(
        bytes32 ref,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external view returns (bool) {
        if (proof.length != 65) return false;

        bytes32 message = keccak256(abi.encodePacked(ref, to, amount, chainId));
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
        return recovered == bitgoSigner;
    }
}