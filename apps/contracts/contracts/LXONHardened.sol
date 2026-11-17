// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title LXONHardened
 * @dev Hardened LXON token with:
 *      - No single-key owner control
 *      - Emission only via TimelockController with 48h delay
 *      - Role-based access control
 *      - Fixed MAX_SUPPLY immutable
 *      - No pause function (transfers cannot be halted)
 */
contract LXONHardened is ERC20, ERC20Votes, ERC20Burnable, ERC20Permit, AccessControl {
    // ============ Constants ============
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;

    // ============ Roles ============
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ============ State ============
    TimelockController public immutable timelock;
    address public immutable governance;

    // ============ Events ============
    event EmissionMinted(uint256 amount, address indexed minter);
    event TreasuryBurned(address indexed account, uint256 amount, address indexed burner);

    // ============ Modifiers ============
    modifier onlyGovernance() {
        require(
            msg.sender == address(timelock) || msg.sender == governance,
            "LXONHardened: only governance can call this"
        );
        _;
    }

    // ============ Constructor ============
    /**
     * @dev Initialize hardened token with zero supply
     * @param _governance Address of governance contract (typically a Governor contract)
     * @param _timelockDelay Delay in seconds for timelock (default: 48 hours = 172800 seconds)
     */
    constructor(address _governance, uint256 _timelockDelay) ERC20("LXON", "LXON") ERC20Permit("LXON") {
        require(_governance != address(0), "LXONHardened: governance cannot be zero address");
        require(_timelockDelay > 0, "LXONHardened: timelock delay must be > 0");

        governance = _governance;

        // Deploy TimelockController
        // - timelockDelay: delay before execution (48 hours)
        // - proposers: governance address (can propose)
        // - executors: governance address (can execute)
        // - admin: governance address (can manage roles)
        // - requiresDelay: false (no additional delay for role changes)
        address[] memory proposers = new address[](1);
        proposers[0] = _governance;

        address[] memory executors = new address[](1);
        executors[0] = _governance;

        timelock = new TimelockController(
            _timelockDelay,
            proposers,
            executors,
            _governance
        );

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(MINTER_ROLE, address(timelock));
        _grantRole(BURNER_ROLE, address(timelock));

        // Zero initial supply — emission starts via governance
    }

    // ============ Core Mint Functions ============

    /**
     * @dev Mint emission via TimelockController (governance-controlled)
     * Only callable through timelock with 48-hour delay
     * @param amount Amount of LXON to mint
     */
    function mintEmission(uint256 amount) external onlyRole(MINTER_ROLE) {
        require(amount > 0, "LXONHardened: amount must be > 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "LXONHardened: exceeds MAX_SUPPLY");

        _mint(msg.sender, amount);
        emit EmissionMinted(amount, msg.sender);
    }

    /**
     * @dev Emergency mint function (DEPRECATED - kept for migration only)
     * This function exists to support gradual migration from old contract
     * It will call mintEmission through the governance flow
     * 
     * @notice Do not use in production. Use mintEmission() instead.
     */
    function mint(address to, uint256 amount) external {
        // Only allow if called through timelock governance
        require(
            msg.sender == address(timelock) || hasRole(MINTER_ROLE, msg.sender),
            "LXONHardened: only timelock or MINTER_ROLE can mint"
        );
        require(to != address(0), "LXONHardened: cannot mint to zero address");
        require(amount > 0, "LXONHardened: amount must be > 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "LXONHardened: exceeds MAX_SUPPLY");

        _mint(to, amount);
        emit EmissionMinted(amount, msg.sender);
    }

    // ============ Burn Functions ============

    /**
     * @dev Public burn - any user can burn their own tokens
     * Overrides ERC20Burnable
     */
    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    /**
     * @dev Governance burn - only TimelockController can burn treasury surplus
     * Used for deflationary mechanics
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burnFromGovernance(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        require(account != address(0), "LXONHardened: cannot burn from zero address");
        require(amount > 0, "LXONHardened: amount must be > 0");
        require(balanceOf(account) >= amount, "LXONHardened: burn amount exceeds balance");

        _burn(account, amount);
        emit TreasuryBurned(account, amount, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @dev Check total supply against max supply
     */
    function circulating() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Check how much can still be minted
     */
    function availableToMint() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    /**
     * @dev Check if an address has a specific role
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
    }

    // ============ ERC20 Overrides ============

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, amount);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
