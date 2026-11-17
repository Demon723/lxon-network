// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * SanctionsOracle
 * ---------------
 * On-chain mirror of OFAC SDN, EU consolidated, and UN sanctions lists.
 * Off-chain service pushes Merkle roots of the sanctioned address set;
 * on-chain we verify Merkle proofs for specific addresses.
 *
 * This avoids storing the full list on-chain (~60k+ addresses) while
 * keeping verification cheap.
 */
contract SanctionsOracle is Ownable2Step {
    bytes32 public ofacRoot;
    bytes32 public euRoot;
    bytes32 public unRoot;
    uint64  public lastUpdated;

    mapping(address => bool) public manualBlock;   // direct additions

    event RootsUpdated(bytes32 ofac, bytes32 eu, bytes32 un, uint64 at);
    event ManualBlock(address indexed who, bool blocked);

    constructor() Ownable(msg.sender) {}

    function updateRoots(bytes32 _ofac, bytes32 _eu, bytes32 _un) external onlyOwner {
        ofacRoot = _ofac;
        euRoot = _eu;
        unRoot = _un;
        lastUpdated = uint64(block.timestamp);
        emit RootsUpdated(_ofac, _eu, _un, uint64(block.timestamp));
    }

    function setManual(address who, bool blocked) external onlyOwner {
        manualBlock[who] = blocked;
        emit ManualBlock(who, blocked);
    }

    /// @notice Verify a Merkle proof against one of the lists.
    function verify(bytes32 listRoot, bytes32 leaf, bytes32[] calldata proof) public pure returns (bool) {
        bytes32 h = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            h = h < proof[i] ? keccak256(abi.encodePacked(h, proof[i])) : keccak256(abi.encodePacked(proof[i], h));
        }
        return h == listRoot;
    }

    function isSanctioned(address who, bytes32[] calldata ofacProof) external view returns (bool) {
        if (manualBlock[who]) return true;
        if (ofacRoot == bytes32(0)) return false;
        return verify(ofacRoot, keccak256(abi.encodePacked(who)), ofacProof);
    }
}
