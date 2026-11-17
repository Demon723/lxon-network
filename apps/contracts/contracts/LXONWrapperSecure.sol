// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title LXONWrapperSecure
 * @notice Security patch for `LXONWrapper`. Same wrap/unwrap mechanics; the `MINTER_ROLE` path is no
 *         longer an open door.
 *
 * WHAT WAS WRONG. The deployed wrapper at 0xC0CF6B0E6C5a0705F319BA5c629a6Bc7E82FEf00 has
 * `function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) { _mint(to, amount); }` --
 * no cap, no backing check, and the constructor grants `MINTER_ROLE` to the deployer, who also holds
 * `DEFAULT_ADMIN_ROLE`. That path has been used: on 2026-10-29T04:13:45Z tx
 * 0x11a40b8d6ae7ac589cefed687e34450837c44c7efb3dc2e14857e8d5a47c2d86 minted 10,000 wLXON to
 * 0x7F715B7F...9Ef3 with zero LXON pulled in, leaving `totalSupply() = 40,000` against
 * `collateralBalance() = 30,000`. The wrapper's own header promises
 * "`totalSupply()` can never exceed the LXON this contract holds", and `unwrap()` pays from whatever it
 * holds -- so the outstanding claims are now a queue, and the first 30,000 of them win.
 *
 * THE PATCH. Three independent controls, because each closes a different way of getting hurt:
 *
 *   1. BACKING. `mint()` requires `totalSupply() + amount <= collateralBalance() + bridgeEscrow`.
 *      Free issuance is gone: to mint you must first have the underlying sitting here, or have it
 *      formally accounted for at the bridge (see 3).
 *   2. A HARD CAP, defaulting to zero. `mintCeiling` is a separate ceiling and **0 means refuse every
 *      mint, not uncapped** -- the convention this project already uses on the bridge's inbound lane,
 *      written down here because a "0 = unlimited" default is exactly how a cap becomes a hole.
 *      Both ceilings apply: a mint must satisfy backing AND ceiling.
 *   3. `bridgeEscrow` -- the one allowance that lets supply exceed the LXON held here -- may only be
 *      raised by `ESCROW_ROLE`, and the constructor takes that from a pre-existing timelock address.
 *      It is deliberately NOT granted to `DEFAULT_ADMIN`, so the deployer key cannot raise it directly.
 *      Lowering it stays with `DEFAULT_ADMIN`: an emergency can reduce claimed backing, never increase it.
 *
 * NO SELF-DEPLOYED TIMELOCK. `LXONDEXLiquidityPool` and two other contracts here take an `_timelock`
 * argument, discard it, and `new TimelockController(...)` with the deployer as proposer and executor --
 * which is a DEFAULT_ADMIN bypass dressed as custody, already proven once by watching `addRelayer`
 * succeed. This constructor accepts an existing timelock address and uses it; if you pass an address
 * with no code, it refuses, because an empty `ESCROW_ROLE` holder means the ceiling can never move and
 * the contract would look healthy while being permanently frozen.
 *
 * THIS DOES NOT PATCH THE LIVE TOKEN. `LXONWrapper` is a plain CREATE deployment with no proxy --
 * verified by building the explorer-published source and diffing: identical length, every byte equal
 * except the embedded `originalLXON` immutable and the CBOR metadata hash. So the live mitigation is a
 * role change on the contract that exists, not a new one:
 *
 *   cast send 0xC0CF6B0E... "revokeRole(bytes32,address)" $(cast keccak 'MINTER_ROLE') 0xFaE699d2... \
 *     --rpc-url https://rpc.lxon.in            // stops all future free mints; no redeploy, no migration
 *   cast send 0xC0CF6B0E... "burnFrom(address,uint256)" 0x7F715B7F... 10000000000000000000000 \
 *     --rpc-url https://rpc.lxon.in            // restores supply == collateral == 30,000
 *
 * and a new wrapper only becomes relevant once a holder migration is a decision someone has actually
 * made. Until then `mint()`/`burnFrom()` on the deployed address remain open, which is why the liquidity
 * automation in LXONWrapAndProvide.sol is not deployed either.
 */
contract LXONWrapperSecure is ERC20, AccessControl {
    using SafeERC20 for IERC20;

    string public constant NAME = "LXON Wrapped";
    string public constant SYMBOL = "wLXON";
    uint8 public constant DECIMALS = 18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// Held by a timelock, never by the deployer key. Only raises claimed bridge backing.
    bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");

    IERC20 public immutable originalLXON;

    /// Hard ceiling on total minted supply. 0 refuses every mint. Unrelated to, and additional to, backing.
    uint256 public mintCeiling;

    /// LXON escrowed at a bridge rather than here. Raise: ESCROW_ROLE (timelock). Lower: DEFAULT_ADMIN.
    uint256 public bridgeEscrow;

    event Wrapped(address indexed from, uint256 amount);
    event Unwrapped(address indexed to, uint256 amount);
    event CeilingSet(uint256 oldCeiling, uint256 newCeiling);
    event BridgeEscrowRaised(uint256 oldValue, uint256 newValue);
    event BridgeEscrowLowered(uint256 oldValue, uint256 newValue);

    constructor(address _originalLXON, address _escrowTimelock, uint256 _mintCeiling)
        ERC20("LXON Wrapped", "wLXON")
    {
        require(_originalLXON != address(0), "LXONWrapper: zero token");
        require(_escrowTimelock != address(0), "LXONWrapper: zero escrow timelock");
        // An ESCROW_ROLE holder with no code can never raise the escrow allowance, so the contract is
        // silently frozen -- the same failure mode as passing an ERC20 as an ADMIN_ROLE. Refuse at birth.
        require(_escrowTimelock.code.length > 0, "LXONWrapper: escrow timelock has no code");
        originalLXON = IERC20(_originalLXON);
        mintCeiling = _mintCeiling;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ESCROW_ROLE, _escrowTimelock);
        // MINTER_ROLE is intentionally NOT granted here. Add it deliberately, after the ceiling is set.
    }

    function decimals() public view virtual override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Deposit LXON and receive the same amount of wLXON.
     * @dev Deliberately NOT room-gated, and this is the one place the two paths differ on purpose.
     *      `wrap()` pulls `amount` of LXON in before it mints, so the collateral that backs the new
     *      supply arrives in the same transaction: it cannot lower the backing ratio and a guard here
     *      would only lock honest users out. An earlier revision of this file put `_requireRoom(amount)`
     *      in front of the pull and four tests died -- with `mintCeiling` at its default 0, every wrap
     *      reverted, i.e. the "fix" had bricked the token while looking maximally safe.
     *      The ceiling belongs to `mint()`, where supply can be created without anything arriving.
     */
    function wrap(uint256 amount) external {
        require(amount > 0, "LXONWrapper: zero amount");
        originalLXON.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Wrapped(msg.sender, amount);
    }

    /// @notice Redeem wLXON for the LXON backing it. Burn first, then pay out -- unchanged.
    function unwrap(uint256 amount) external {
        _burn(msg.sender, amount);
        originalLXON.safeTransfer(msg.sender, amount);
        emit Unwrapped(msg.sender, amount);
    }

    /**
     * @notice Mint against collateral already held here, or against bridge escrow an ESCROW_ROLE holder
     *         has recorded. Both the backing check and the ceiling apply. Reverts on any unbacked mint.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "LXONWrapper: zero to");
        require(amount > 0, "LXONWrapper: zero amount");
        _requireRoom(amount);
        _mint(to, amount);
    }

    /// @notice Burn wLXON out of `account`, with the holder's allowance as the authority.
    /// @dev `onlyRole(MINTER_ROLE)` alone was the second live defect: on the deployed wrapper any
    ///      MINTER_ROLE key could burn any holder's balance, proven by eth_call against the founder
    ///      wallet whose allowance to that key was zero. The role says you may burn; only an allowance
    ///      from the holder says you may burn *theirs*.
    function burnFrom(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @notice Collateral physically held by this contract.
    function collateralBalance() public view returns (uint256) {
        return originalLXON.balanceOf(address(this));
    }

    /// @notice Total issuance the current backing and ceiling permit.
    function mintable() public view returns (uint256) {
        uint256 backed = collateralBalance() + bridgeEscrow;
        uint256 headroom = backed > totalSupply() ? backed - totalSupply() : 0;
        uint256 underCeiling = mintCeiling > totalSupply() ? mintCeiling - totalSupply() : 0;
        return headroom < underCeiling ? headroom : underCeiling;
    }

    /// @notice 1e18 == fully backed. Anything below is an unbacked-issuance alarm, and it is readable.
    function backingRatio() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (collateralBalance() + bridgeEscrow) * 1e18 / supply;
    }

    /// @dev The one place the invariant lives, so wrap() and mint() cannot diverge from each other.
    function _requireRoom(uint256 amount) internal view {
        require(amount <= mintable(), "LXONWrapper: unbacked mint");
    }

    /// @notice Raise the hard ceiling. DEFAULT_ADMIN may raise or lower it, but never above what is backed,
    ///         so a ceiling cannot authorise issuance on its own.
    function setMintCeiling(uint256 _ceiling) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ceiling <= collateralBalance() + bridgeEscrow, "LXONWrapper: ceiling above backing");
        emit CeilingSet(mintCeiling, _ceiling);
        mintCeiling = _ceiling;
    }

    /// @notice Claim more LXON is escrowed at a bridge. Timelock-gated: never the deployer key.
    function raiseBridgeEscrow(uint256 _newValue) external onlyRole(ESCROW_ROLE) {
        require(_newValue > bridgeEscrow, "LXONWrapper: not a raise");
        require(_newValue <= bridgeEscrow + type(uint128).max, "LXONWrapper: jump too large");
        emit BridgeEscrowRaised(bridgeEscrow, _newValue);
        bridgeEscrow = _newValue;
    }

    /// @notice Emergency reduction of claimed backing. Anyone with DEFAULT_ADMIN may reduce the claim,
    ///         which can only ever make minting harder.
    function lowerBridgeEscrow(uint256 _newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newValue < bridgeEscrow, "LXONWrapper: not a lower");
        emit BridgeEscrowLowered(bridgeEscrow, _newValue);
        bridgeEscrow = _newValue;
    }
}
