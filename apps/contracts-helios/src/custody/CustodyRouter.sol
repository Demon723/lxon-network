// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * CustodyRouter
 * -------------
 * Unified entry point for all custodian attestations. Routes to the
 * correct adapter based on the custodian's asset ID.
 */
contract CustodyRouter is Ownable2Step {
    mapping(bytes32 => address) public adapters;  // keccak256("BITGO"|...) => adapter
    mapping(address => bool) public relayers;

    event AdapterRegistered(bytes32 indexed name, address adapter);
    event RelayerSet(address indexed who, bool allowed);

    error UnknownCustodian();
    error NotRelayer();
    error InvalidProof();

    modifier onlyRelayer() { if (!relayers[msg.sender] && msg.sender != owner()) revert NotRelayer(); _; }

    constructor() Ownable(msg.sender) {}

    function registerAdapter(bytes32 name, address adapter) external onlyOwner {
        adapters[name] = adapter;
        emit AdapterRegistered(name, adapter);
    }

    function setRelayer(address who, bool allowed) external onlyOwner {
        relayers[who] = allowed;
        emit RelayerSet(who, allowed);
    }

    function verify(bytes32 custodianName, bytes32 ref, address to, uint256 amount, bytes calldata proof) external view returns (bool) {
        address adapter = adapters[custodianName];
        if (adapter == address(0)) revert UnknownCustodian();

        (bool ok, bytes memory ret) = adapter.staticcall(
            abi.encodeWithSignature("verifyDeposit(bytes32,address,uint256,bytes)", ref, to, amount, proof)
        );
        if (!ok || ret.length < 32) return false;
        return abi.decode(ret, (bool));
    }
}
