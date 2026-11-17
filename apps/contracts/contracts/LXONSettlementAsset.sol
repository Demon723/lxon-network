// SPDX-License-Identifier: MIT
// LXON Reserve-Backed Settlement Token — reference implementation
// Requires: OpenZeppelin Contracts v4.x | Compiler: Solidity 0.8.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract LXONSettlementAsset is ERC20, AccessControl, Pausable {
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");         // 3-of-5 validator multi-sig
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");     // publishes attested reserve ceiling
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE"); // 2-of-5 emergency pause

    uint256 public reserveCeiling; // attested reserves in USD cents
    uint256 public pendingRedeem;  // fiat wires in flight (burned, not yet paid)

    event Minted(address indexed to, uint256 amount, bytes32 depositRef);
    event Redeemed(address indexed from, uint256 amount, bytes32 wireRef);
    event CeilingUpdated(uint256 newCeiling, bytes32 attestationHash);

    constructor(address admin)
        ERC20("LXON Settlement Asset", "LXON")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mint only against a confirmed custodian deposit (1 USD = 1 LXON).
    /// @param to institution wallet receiving LXON
    /// @param usdCents confirmed deposit value in USD cents (6-decimal parity)
    /// @param depositRef custodian deposit confirmation reference
    function mint(address to, uint256 usdCents, bytes32 depositRef)
        external onlyRole(MINT_ROLE) whenNotPaused
    {
        uint256 amount = usdCents * 1e4; // 6-decimals: 1 cent -> 10,000 units
        require(totalSupply() + amount <= (reserveCeiling - pendingRedeem) * 1e4,
            "LXON: exceeds attested reserves");
        _mint(to, amount);
        emit Minted(to, amount, depositRef);
    }

    /// @notice Redemption: burn first, wire fiat T+1 off-chain.
    function redeem(uint256 amount, bytes32 wireRef)
        external whenNotPaused
    {
        require(balanceOf(msg.sender) >= amount, "LXON: insufficient balance");
        _burn(msg.sender, amount);
        pendingRedeem += amount / 1e4;
        emit Redeemed(msg.sender, amount, wireRef);
    }

    /// @notice Oracle publishes the latest attested reserve ceiling.
    function updateCeiling(uint256 usdCents, bytes32 attestationHash)
        external onlyRole(ORACLE_ROLE)
    {
        reserveCeiling = usdCents;
        emit CeilingUpdated(usdCents, attestationHash);
    }

    /// @notice Guardian clears pending redemptions once wires settle off-chain.
    function settleRedeemed(uint256 usdCents)
        external onlyRole(GUARDIAN_ROLE)
    {
        require(usdCents <= pendingRedeem, "LXON: over-settle");
        pendingRedeem -= usdCents;
    }

    // ---- Emergency controls ----
    function pause() external onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external onlyRole(MINT_ROLE) { _unpause(); }
}