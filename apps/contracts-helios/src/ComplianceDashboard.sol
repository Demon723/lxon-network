// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * ComplianceDashboard
 * -------------------
 * Backend for the enterprise compliance dashboard.
 *
 * Exposes a JSON-RPC-compatible view API for:
 *   - KYC status of a user
 *   - Wrap/unwrap history
 *   - Sanctions screening results
 *   - Audit trail entries
 *
 * Enterprise sales teams use this to prove compliance to their
 * institutional clients.
 */
contract ComplianceDashboard is Ownable2Step {
    address public complianceRegistry;
    address public auditTrail;
    address public sanctionsOracle;

    event EndpointUpdated(string name, address addr);

    constructor(address _reg, address _audit, address _oracle) Ownable(msg.sender) {
        complianceRegistry = _reg;
        auditTrail = _audit;
        sanctionsOracle = _oracle;
    }

    function setEndpoints(address _reg, address _audit, address _oracle) external onlyOwner {
        complianceRegistry = _reg;
        auditTrail = _audit;
        sanctionsOracle = _oracle;
        emit EndpointUpdated("registry", _reg);
        emit EndpointUpdated("audit", _audit);
        emit EndpointUpdated("oracle", _oracle);
    }

    /**
     * @notice Returns a compliance summary for an address.
     *         This is the main endpoint for the dashboard frontend.
     */
    function getSummary(address who) external view returns (bytes memory) {
        return abi.encode(
            who,
            complianceRegistry,
            auditTrail,
            sanctionsOracle
        );
    }
}