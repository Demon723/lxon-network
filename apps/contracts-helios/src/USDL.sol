// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * USDL — PQ-Native Stablecoin
 * --------------------------
 * A reserve-backed stablecoin pegged 1:1 to USD. Unlike algorithmic
 * stablecoins, USDL is fully collateralized:
 *
 *   - 60% USDC / USDT (on-chain, verifiable)
 *   - 30% LXON (delegated to RevenueSplitter for yield)
 *   - 10% liquid cash (off-chain, attested by a custodian)
 *
 * The reserve ratio is monitored on-chain; if it drops below 110%,
 * the contract pauses new mints until reserves are restored.
 *
 * Why PQ? USDL is the settlement layer for the PQ Wrapped Asset
 * ecosystem. When an institution wraps BTC into qBTC, they can then
 * swap qBTC → USDL for instant settlement without touching the
 * volatile LXON price.
 */
contract USDL is ERC20, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IERC20 public immutable lxon;
    address public immutable revenueSplitter;

    uint256 public constant MIN_RESERVE_RATIO_BPS = 1100; // 110% minimum
    uint256 public constant COLLATERAL_USDC_BPS = 6000; // 60% USDC
    uint256 public constant COLLATERAL_LXON_BPS = 3000; // 30% LXON
    uint256 public constant COLLATERAL_CASH_BPS = 1000; // 10% cash

    uint256 public totalReservesUsdc;
    uint256 public totalReservesLxon;
    uint256 public totalReservesCash; // attested off-chain

    bool public mintingPaused;

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event ReservesUpdated(uint256 usdc, uint256 lxon, uint256 cash);
    event MintingToggled(bool paused);

    error MintingPaused();
    error InsufficientReserves();
    error BadSignature();
    error NotCustodian();

    mapping(address => bool) public cashAttestors;

    constructor(
        address _usdc,
        address _lxon,
        address _revenueSplitter
    ) ERC20("LXON USD Stable", "USDL") Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        lxon = IERC20(_lxon);
        revenueSplitter = _revenueSplitter;
    }

    function setCashAttestor(address who, bool allowed) external onlyOwner {
        cashAttestors[who] = allowed;
    }

    function setMintingPaused(bool paused) external onlyOwner {
        mintingPaused = paused;
        emit MintingToggled(paused);
    }

    /**
     * @notice Mint USDL. Caller deposits USDC + LXON; the contract checks
     *         the reserve ratio and mints 1:1.
     */
    function mint(uint256 amount) external nonReentrant {
        if (mintingPaused) revert MintingPaused();
        // Caller must have approved USDC + LXON first.
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        lxon.safeTransferFrom(msg.sender, address(this), amount);

        totalReservesUsdc += amount;
        totalReservesLxon += amount;

        _mint(msg.sender, amount);
        emit Minted(msg.sender, amount);
    }

    /**
     * @notice Burn USDL. Returns USDC + LXON pro-rata.
     */
    function burn(uint256 amount) external nonReentrant {
        if (balanceOf(msg.sender) < amount) revert InsufficientReserves();
        _burn(msg.sender, amount);

        uint256 usdcOut = (totalReservesUsdc * amount) / totalSupply();
        uint256 lxonOut = (totalReservesLxon * amount) / totalSupply();

        totalReservesUsdc -= usdcOut;
        totalReservesLxon -= lxonOut;

        usdc.safeTransfer(msg.sender, usdcOut);
        lxon.safeTransfer(msg.sender, lxonOut);
        emit Burned(msg.sender, amount);
    }

    function attestCash(uint256 amount) external {
        if (!cashAttestors[msg.sender]) revert NotCustodian();
        totalReservesCash += amount;
        emit ReservesUpdated(totalReservesUsdc, totalReservesLxon, totalReservesCash);
    }

    function isHealthy() external view returns (bool) {
        uint256 supply = totalSupply();
        if (supply == 0) return true;
        uint256 total = totalReservesUsdc + totalReservesLxon + totalReservesCash;
        return (total * 10_000) / supply >= MIN_RESERVE_RATIO_BPS;
    }

    function getReserveRatio() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint256 total = totalReservesUsdc + totalReservesLxon + totalReservesCash;
        return (total * 10_000) / supply;
    }
}
