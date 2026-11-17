// SPDX-License-Identifier: MIT
// LXON Reserve-Backed Settlement Token — reference implementation
// Requires: OpenZeppelin Contracts v5.x | Compiler: Solidity 0.8.24+
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LXON is ERC20, AccessControl, Pausable, Ownable {
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 public reserveCeiling;
    uint256 public pendingRedeem;

    event Minted(address indexed to, uint256 amount, bytes32 depositRef);
    event Redeemed(address indexed from, uint256 amount, bytes32 wireRef);
    event CeilingUpdated(uint256 newCeiling, bytes32 attestationHash);

    constructor(address admin)
        ERC20("LXON Settlement Asset", "LXON")
        Ownable(admin)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 usdCents, bytes32 depositRef)
        external onlyRole(MINT_ROLE) whenNotPaused
    {
        uint256 amount = usdCents * 1e4;
        require(totalSupply() + amount <= (reserveCeiling - pendingRedeem) * 1e4,
            "LXON: exceeds attested reserves");
        _mint(to, amount);
        emit Minted(to, amount, depositRef);
    }

    function redeem(uint256 amount, bytes32 wireRef)
        external whenNotPaused
    {
        require(balanceOf(msg.sender) >= amount, "LXON: insufficient balance");
        _burn(msg.sender, amount);
        pendingRedeem += amount / 1e4;
        emit Redeemed(msg.sender, amount, wireRef);
    }

    function updateCeiling(uint256 usdCents, bytes32 attestationHash)
        external onlyRole(ORACLE_ROLE)
    {
        reserveCeiling = usdCents;
        emit CeilingUpdated(usdCents, attestationHash);
    }

    function settleRedeemed(uint256 usdCents)
        external onlyRole(GUARDIAN_ROLE)
    {
        require(usdCents <= pendingRedeem, "LXON: over-settle");
        pendingRedeem -= usdCents;
    }

    function pause() external virtual onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external virtual onlyRole(MINT_ROLE) { _unpause(); }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}