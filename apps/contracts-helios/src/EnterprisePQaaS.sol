// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * EnterprisePQaaS
 * ---------------
 * Subscription API for enterprise PQ wrapping.
 *
 * Enterprises pay a monthly fee (in USDL or LXON) to access:
 *   - Dedicated custodian adapters (BitGo, Anchorage, Copper)
 *   - Priority attestation processing
 *   - Dedicated API keys
 *   - SLA-backed uptime
 *
 * This is the revenue layer that funds protocol buybacks.
 */
contract EnterprisePQaaS is Ownable2Step, ReentrancyGuard {
    enum Tier { Free, Pro, Enterprise }

    struct Subscription {
        address enterprise;
        Tier tier;
        uint64 startedAt;
        uint64 expiresAt;
        uint256 monthlyFee; // in USDL wei
        bool active;
    }

    uint256 public constant FREE_QUOTE = 100 ether; // 100 USDL
    uint256 public constant PRO_FEE = 10_000 ether; // 10k USDL/month
    uint256 public constant ENT_FEE = 100_000 ether; // 100k USDL/month

    mapping(bytes32 => Subscription) public subscriptions;
    mapping(address => bytes32) public activeSub;
    bytes32[] public subIds;

    event Subscribed(bytes32 indexed subsId, address indexed enterprise, Tier tier);
    event Renewed(bytes32 indexed subsId);
    event Expired(bytes32 indexed subsId);

    error NotSubscribed();
    error AlreadySubscribed();
    error Expired_();

    constructor() Ownable(msg.sender) {}

    function subscribe(Tier tier) external nonReentrant {
        if (activeSub[msg.sender] != bytes32(0)) revert AlreadySubscribed();

        uint256 fee;
        if (tier == Tier.Free) fee = 0;
        else if (tier == Tier.Pro) fee = PRO_FEE;
        else fee = ENT_FEE;

        bytes32 id = keccak256(abi.encodePacked(msg.sender, tier, block.timestamp));

        subscriptions[id] = Subscription({
            enterprise: msg.sender,
            tier: tier,
            startedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp) + 30 days,
            monthlyFee: fee,
            active: true
        });
        activeSub[msg.sender] = id;
        subIds.push(id);

        emit Subscribed(id, msg.sender, tier);
    }

    function renew(bytes32 id) external nonReentrant {
        Subscription storage s = subscriptions[id];
        if (s.enterprise != msg.sender) revert NotSubscribed();
        if (!s.active) revert Expired_();
        s.expiresAt = uint64(block.timestamp) + 30 days;
        emit Renewed(id);
    }

    function isActive(address enterprise) external view returns (bool) {
        bytes32 id = activeSub[enterprise];
        if (id == bytes32(0)) return false;
        return subscriptions[id].active && block.timestamp <= subscriptions[id].expiresAt;
    }

    function quotaRemaining(address enterprise) external view returns (uint256) {
        bytes32 id = activeSub[enterprise];
        if (id == bytes32(0)) return 0;
        Subscription storage s = subscriptions[id];
        if (!s.active || block.timestamp > s.expiresAt) return 0;
        if (s.tier == Tier.Free) return FREE_QUOTE;
        return type(uint256).max;
    }
}