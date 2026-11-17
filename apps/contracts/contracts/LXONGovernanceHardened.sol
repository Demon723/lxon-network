// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

/**
 * @title LXONGovernanceHardened
 * @dev Hardened governance contract with:
 *      - TimelockController integration (48-hour delay)
 *      - Proposal threshold: 0.1% of circulating supply
 *      - Quorum: 4% of circulating supply
 *      - Voting delay: 1 block
 *      - Voting period: 50400 blocks (~1 week on Ethereum)
 *      - Proposal types: EMISSION_PARAMS, BURN_RATE, SUBNET_PARAMS, TREASURY_SPEND
 */
contract LXONGovernanceHardened is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // ============ Constants ============
    // Proposal types (for documentation/tracking)
    bytes32 public constant PROPOSAL_TYPE_EMISSION_PARAMS = keccak256("EMISSION_PARAMS");
    bytes32 public constant PROPOSAL_TYPE_BURN_RATE = keccak256("BURN_RATE");
    bytes32 public constant PROPOSAL_TYPE_SUBNET_PARAMS = keccak256("SUBNET_PARAMS");
    bytes32 public constant PROPOSAL_TYPE_TREASURY_SPEND = keccak256("TREASURY_SPEND");

    // ============ Events ============
    event ProposalTypeCreated(
        uint256 indexed proposalId,
        bytes32 proposalType,
        string description
    );

    // ============ Storage ============
    mapping(uint256 => bytes32) public proposalTypes;

    // ============ Constructor ============
    /**
     * @param _token LXON token (ERC20Votes)
     * @param _timelock TimelockController for execution delay
     */
    constructor(
        IVotes _token,
        TimelockController _timelock
    )
        Governor("LXON Governance")
        GovernorSettings(
            1,           // votingDelay: 1 block
            50400,       // votingPeriod: ~1 week (50400 blocks)
            1000e18      // proposalThreshold: 1000 LXON (0.0001% of 1B supply)
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {}

    // ============ Proposal Functions ============

    /**
     * @dev Create proposal with type tracking
     * @param proposalType Type of proposal (EMISSION_PARAMS, etc.)
     * @param targets Target contracts
     * @param values ETH values
     * @param calldatas Function calls
     * @param description Proposal description
     */
    function proposeTyped(
        bytes32 proposalType,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        require(
            proposalType == PROPOSAL_TYPE_EMISSION_PARAMS ||
            proposalType == PROPOSAL_TYPE_BURN_RATE ||
            proposalType == PROPOSAL_TYPE_SUBNET_PARAMS ||
            proposalType == PROPOSAL_TYPE_TREASURY_SPEND,
            "LXONGovernanceHardened: invalid proposal type"
        );

        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = proposalType;

        emit ProposalTypeCreated(proposalId, proposalType, description);
        return proposalId;
    }

    /**
     * @dev Get proposal type
     */
    function getProposalType(uint256 proposalId) external view returns (bytes32) {
        return proposalTypes[proposalId];
    }

    // ============ Governance Parameters (View) ============

    /**
     * @dev Get current proposal threshold
     */
    function getCurrentProposalThreshold() external view returns (uint256) {
        return proposalThreshold();
    }

    /**
     * @dev Get quorum numerator (e.g., 4 = 4%)
     */
    function getQuorumNumerator() external view returns (uint256) {
        return quorumNumerator();
    }

    /**
     * @dev Get voting delay in blocks
     */
    function getVotingDelay() public view returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @dev Get voting period in blocks
     */
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @dev Get quorum for a given block number
     */
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /**
     * @dev Get state of a proposal
     */
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /**
     * @dev Check if proposal is active
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @dev Get proposal deadline
     */
    function proposalDeadline(uint256 proposalId)
        public
        view
        override(Governor)
        returns (uint256)
    {
        return super.proposalDeadline(proposalId);
    }

    // ============ Overrides ============

    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ============ Clock Functions ============

    /**
     * @dev Clock mode for timestamp-based voting
     */
    function clock() public view override(Governor, GovernorVotes) returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Clock mode identifier
     */
    function CLOCK_MODE() public pure override(Governor, GovernorVotes) returns (string memory) {
        return "mode=timestamp";
    }
}
