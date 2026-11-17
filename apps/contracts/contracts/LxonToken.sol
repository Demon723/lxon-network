// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LXON
 * @notice Public ERC20 token for the LXON ecosystem on Chain 724.
 *
 * Design principles:
 *   - Transfers are unrestricted. No whitelist, no blacklist, no pause.
 *   - Mint and burn are role-gated so the bridge can operate.
 *   - Fixed 6 decimals, matching the existing LXON token spec.
 *   - No fee-on-transfer, no rebasing, no hooks.
 *
 * Roles:
 *   DEFAULT_ADMIN_ROLE — can grant/revoke all other roles
 *   MINTER_ROLE        — can mint new supply (bridge, treasury)
 *   BURNER_ROLE        — can burn from any address (bridge)
 */
contract LxonToken {
    string public constant name = "LXON";
    string public constant symbol = "LXON";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* ----------------------------- Roles ----------------------------- */

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(bytes32 => bytes32) public getRoleAdmin;

    /* ----------------------------- Events ---------------------------- */

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /* --------------------------- Modifiers --------------------------- */

    modifier onlyRole(bytes32 role) {
        require(hasRole[role][msg.sender], "LXON: UNAUTHORIZED");
        _;
    }

    /* -------------------------- Constructor -------------------------- */

    /**
     * @param admin          Address that receives DEFAULT_ADMIN_ROLE.
     *                       Use a multisig in production.
     * @param initialHolder  Address that receives the initial supply.
     *                       Pass address(0) to skip initial mint.
     * @param initialSupply  Amount in base units (6 decimals).
     *                       Pass 0 to skip initial mint.
     */
    constructor(address admin, address initialHolder, uint256 initialSupply) {
        require(admin != address(0), "LXON: ZERO_ADMIN");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        if (initialSupply > 0 && initialHolder != address(0)) {
            _mint(initialHolder, initialSupply);
        }
    }

    /* --------------------------- ERC20 core -------------------------- */

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "LXON: ALLOWANCE");
            _approve(from, msg.sender, allowed - value);
        }
        _transfer(from, to, value);
        return true;
    }

    /* --------------------------- Mint / burn ------------------------- */

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /* ---------------------------- Internal --------------------------- */

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "LXON: FROM_ZERO");
        require(to != address(0), "LXON: TO_ZERO");
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "LXON: BALANCE");
        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "LXON: OWNER_ZERO");
        require(spender != address(0), "LXON: SPENDER_ZERO");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "LXON: MINT_TO_ZERO");
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "LXON: BURN_FROM_ZERO");
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= amount, "LXON: BURN_BALANCE");
        unchecked {
            balanceOf[from] = fromBalance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    /* --------------------------- Role admin -------------------------- */

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole[role][account], "LXON: NOT_ROLE");
        hasRole[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function renounceRole(bytes32 role, address account) external {
        require(account == msg.sender, "LXON: SELF_ONLY");
        require(hasRole[role][account], "LXON: NOT_ROLE");
        hasRole[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), "LXON: ZERO_ACCOUNT");
        if (!hasRole[role][account]) {
            hasRole[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /* ----------------------------- Views ----------------------------- */

    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
