// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * ComplianceRegistry
 * ------------------
 * KYC/AML gate for wrapped-asset operations. Users must be verified
 * before wrapping more than `unverifiedThreshold`.
 *
 * Stores tier (0=unverified, 1=basic, 2=accredited, 3=institutional),
 * jurisdiction code, and expiry. Attested by whitelisted KYC providers.
 */
contract ComplianceRegistry is Ownable2Step {
    enum Tier { Unverified, Basic, Accredited, Institutional }

    struct Record {
        Tier    tier;
        uint16  jurisdiction;   // ISO 3166-1 numeric
        uint64  verifiedAt;
        uint64  expiresAt;
        bytes32 providerRef;
    }

    mapping(address => Record) public records;
    mapping(address => bool) public providers;
    mapping(address => bool) public blocked;   // sanctions, banned

    uint256 public unverifiedThreshold = 1_000 ether;

    event ProviderSet(address indexed who, bool allowed);
    event Verified(address indexed who, Tier tier, uint16 jurisdiction, uint64 expiresAt);
    event Revoked(address indexed who, string reason);
    event Blocked(address indexed who, string reason);

    error NotProvider();
    error Blocked_();
    error NotVerified();
    error Expired();

    modifier onlyProvider() { if (!providers[msg.sender] && msg.sender != owner()) revert NotProvider(); _; }

    constructor() Ownable(msg.sender) {}

    function setProvider(address who, bool allowed) external onlyOwner { providers[who] = allowed; emit ProviderSet(who, allowed); }
    function setUnverifiedThreshold(uint256 t) external onlyOwner { unverifiedThreshold = t; }

    function setVerified(address who, Tier tier, uint16 jurisdiction, uint64 expiresAt, bytes32 ref) external onlyProvider {
        records[who] = Record({ tier: tier, jurisdiction: jurisdiction, verifiedAt: uint64(block.timestamp), expiresAt: expiresAt, providerRef: ref });
        emit Verified(who, tier, jurisdiction, expiresAt);
    }

    function revoke(address who, string calldata reason) external onlyProvider {
        delete records[who];
        emit Revoked(who, reason);
    }

    function block_(address who, string calldata reason) external onlyProvider {
        blocked[who] = true;
        emit Blocked(who, reason);
    }

    function unblock(address who) external onlyOwner { blocked[who] = false; }

    function isCompliant(address who) external view returns (bool) {
        if (blocked[who]) return false;
        Record storage r = records[who];
        if (r.tier == Tier.Unverified) return false;
        if (r.expiresAt != 0 && block.timestamp > r.expiresAt) return false;
        return true;
    }

    /// @notice Returns true if the user can wrap any amount (verified or under threshold)
    function canWrap(address who, uint256 amount) external view returns (bool) {
        if (blocked[who]) return false;
        if (amount <= unverifiedThreshold) return true;
        Record storage r = records[who];
        return r.tier != Tier.Unverified && (r.expiresAt == 0 || block.timestamp <= r.expiresAt);
    }
}
