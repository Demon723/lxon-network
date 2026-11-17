// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * GeoFence
 * --------
 * Restricts wrapping/unwrapping by jurisdiction. Uses ISO 3166-1 numeric
 * country codes. Two lists:
 *   - blocked: hard-blocked (sanctioned)
 *   - restricted: needs higher KYC tier
 */
contract GeoFence is Ownable2Step {
    mapping(uint16 => bool) public blocked;
    mapping(uint16 => bool) public restricted;
    mapping(uint16 => uint8) public requiredTier;   // 0..3

    event BlockedJurisdiction(uint16 code, bool blocked);
    event RestrictedJurisdiction(uint16 code, bool restricted, uint8 tier);

    constructor() Ownable(msg.sender) {}

    function setBlocked(uint16 code, bool b) external onlyOwner { blocked[code] = b; emit BlockedJurisdiction(code, b); }
    function setRestricted(uint16 code, bool r, uint8 tier) external onlyOwner {
        restricted[code] = r;
        requiredTier[code] = tier;
        emit RestrictedJurisdiction(code, r, tier);
    }

    function isAllowed(uint16 code, uint8 tier) external view returns (bool) {
        if (blocked[code]) return false;
        if (!restricted[code]) return true;
        return tier >= requiredTier[code];
    }
}
