// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * CopperAdapter
 * -------------
 * Copper uses ClearLoop for off-exchange settlement. Their attestations
 * come from the ClearLoop oracle.
 */
contract CopperAdapter is Ownable2Step {
    address public copperOracle;
    uint256 public chainId;

    constructor(address _oracle, uint256 _chainId) Ownable(msg.sender) {
        copperOracle = _oracle;
        chainId = _chainId;
    }

    function setOracle(address o) external onlyOwner { copperOracle = o; }

    function verifyDeposit(
        bytes32 ref,
        address to,
        uint256 amount,
        bytes calldata proof
    ) external view returns (bool) {
        if (proof.length != 65) return false;

        bytes32 message = keccak256(abi.encodePacked("COPPER", ref, to, amount, chainId));
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
        return recovered == copperOracle;
    }
}