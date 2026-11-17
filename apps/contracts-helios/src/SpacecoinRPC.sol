// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * SpacecoinRPC
 * ------------
 * Thin client for the Spacecoin JSON-RPC endpoint.
 *
 * Spacecoin is LXON's Layer-2 settlement token. This contract wraps the
 * standard JSON-RPC methods needed by the satellite gateway to submit
 * batched anchor transactions and query balances.
 *
 * The RPC endpoint is configured at deploy time (env or governance).
 * The actual JSON-RPC calls are performed off-chain by the gateway
 * operator; this contract stores the endpoint and enforces governance.
 */
contract SpacecoinRPC {
    string public rpcUrl;
    address public governor;

    event RpcUrlUpdated(string indexed url);
    error Unauthorized();

    modifier onlyGovernor() { if (msg.sender != governor) revert Unauthorized(); _; }

    constructor(address _gov, string memory _url) {
        governor = _gov;
        rpcUrl = _url;
    }

    function setRpcUrl(string calldata url) external onlyGovernor {
        rpcUrl = url;
        emit RpcUrlUpdated(url);
    }
}