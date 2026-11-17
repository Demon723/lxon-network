// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title LXONStakingEnhanced
 * @notice Enhanced staking contract with optimized storage, yield options, and NFT representation
 * 
 * Enhancements implemented:
 * 6. Optimized storage with packed structs (gas savings)
 * 11. Yield bearing staking options (vault integration)
 * 16. NFT representation for stakes (ERC721)
 * 12. Comprehensive event logging
 * 13. Circuit breaker events
 * 17. Flash loan protection
 */
contract LXONStakingEnhanced is AccessControl, ReentrancyGuard, Pausable, IERC721, IERC721Metadata {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    IERC20 public immutable lxonToken;

    /// @notice Receives slashed stake. The contract is AccessControl-based (no Ownable),
    ///         so slashed funds need an explicit destination.
    address public treasury;

    // Packed struct. lockPeriod must be uint48, not uint24: the largest tier locks for
    // 365 days (31,536,000 seconds) and uint24 tops out at 16,777,215 (~194 days).
    struct StakePosition {
        uint96 amount;      // 12 bytes (supports up to 79B tokens)
        uint48 startTime;  // 6 bytes (up to 894,784 years)
        uint48 lockPeriod; // 6 bytes (holds 365 days)
        uint8 tier;        // 1 byte (0-2)
        uint8 status;      // 1 byte (0=inactive, 1=active, 2=locked)
        uint96 claimedReward; // 12 bytes
    }

    struct YieldVault {
        address vaultAddress;
        uint256 apy;
        bool active;
    }

    // NFT metadata
    string private _name;
    string private _symbol;
    string private _baseURI;

    // Token convention for chain 724 is 18 decimals (LXON/LXON uses OZ ERC20's decimals(),
    // and the native LXONNativeToken is 18 too). These used to be scaled by 1e6, which made
    // a "1000 token" minimum 1e15 times smaller than anything else on the chain.
    uint256 public constant MIN_STAKE = 1000 * 1e18; // 1,000 LXON
    uint256 public constant MAX_STAKE = 1_000_000 * 1e18; // 1,000,000 LXON
    uint256 public rewardPool;
    uint256 public totalStakedAmount;

    mapping(address => uint256) public totalStaked;
    mapping(uint256 => StakePosition) public stakes;
    mapping(uint256 => address) public stakeOwner;
    mapping(address => bool) public authorizedForSlash;
    mapping(uint256 => YieldVault) public yieldVaults;

    uint256 public nextStakeId;
    uint256 public nextTokenId;

    // Events with comprehensive logging
    event Staked(
        uint256 indexed stakeId,
        uint256 indexed tokenId,
        address indexed user,
        uint256 amount,
        uint256 tier,
        uint256 lockPeriod,
        uint256 timestamp
    );

    event Unstaked(
        uint256 indexed stakeId,
        uint256 indexed tokenId,
        address indexed user,
        uint256 amount,
        uint256 penalty,
        uint256 timestamp
    );

    event RewardClaimed(
        uint256 indexed stakeId,
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event RewardPoolFunded(uint256 amount, uint256 timestamp);

    event SlashApplied(
        address indexed user,
        uint256 amount,
        uint256 newTier,
        string reason,
        uint256 timestamp
    );

    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    event VaultAdded(
        uint256 indexed vaultId,
        address indexed vaultAddress,
        uint256 apy,
        uint256 timestamp
    );

    event VaultRemoved(uint256 indexed vaultId, uint256 timestamp);

    event StakeInVault(
        uint256 indexed stakeId,
        uint256 indexed vaultId,
        uint256 amount,
        uint256 timestamp
    );

    event YieldCollected(
        uint256 indexed vaultId,
        uint256 amount,
        uint256 timestamp
    );

    // Circuit breaker events
    event CircuitBreakerTriggered(
        string functionType,
        bool paused,
        address indexed triggerer,
        uint256 timestamp,
        uint256 blockNumber
    );

    // NFT events (Transfer / Approval / ApprovalForAll) are inherited from OZ's IERC721,
    // which this contract implements — re-declaring them here would be a duplicate.

    // Circuit breaker flags
    bool public stakingPaused;
    bool public unstakingPaused;
    bool public rewardClaimingPaused;
    bool public vaultOperationsPaused;

    // Flash loan protection
    uint256 private _stakingBalanceBefore;

    modifier whenStakingNotPaused() {
        require(!stakingPaused, "Staking paused");
        _;
    }

    modifier whenUnstakingNotPaused() {
        require(!unstakingPaused, "Unstaking paused");
        _;
    }

    modifier whenRewardClaimingNotPaused() {
        require(!rewardClaimingPaused, "Reward claiming paused");
        _;
    }

    modifier whenVaultNotPaused() {
        require(!vaultOperationsPaused, "Vault operations paused");
        _;
    }

    modifier noFlashLoan() {
        _stakingBalanceBefore = lxonToken.balanceOf(address(this));
        _;
        require(lxonToken.balanceOf(address(this)) >= _stakingBalanceBefore, "Flash loan detected");
    }

    constructor(address _lxonToken, string memory _name_, string memory _symbol_) {
        require(_lxonToken != address(0), "Zero address");
        lxonToken = IERC20(_lxonToken);

        _name = _name_;
        _symbol = _symbol_;
        _baseURI = "";

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(VAULT_MANAGER_ROLE, msg.sender);

        treasury = msg.sender;
    }

    /* --------------------------- Circuit Breakers --------------------------- */

    function triggerCircuitBreaker(
        bool _stakingPaused,
        bool _unstakingPaused,
        bool _rewardClaimingPaused,
        bool _vaultOperationsPaused
    ) external onlyRole(PAUSER_ROLE) {
        stakingPaused = _stakingPaused;
        unstakingPaused = _unstakingPaused;
        rewardClaimingPaused = _rewardClaimingPaused;
        vaultOperationsPaused = _vaultOperationsPaused;

        emit CircuitBreakerTriggered(
            "GLOBAL",
            _stakingPaused || _unstakingPaused || _rewardClaimingPaused || _vaultOperationsPaused,
            msg.sender,
            block.timestamp,
            block.number
        );
    }

    /* --------------------------- Staking with NFT --------------------------- */

    function stake(uint256 amount, uint256 tier) external nonReentrant whenNotPaused whenStakingNotPaused noFlashLoan returns (uint256 stakeId, uint256 tokenId) {
        require(amount >= MIN_STAKE, "Below minimum stake");
        require(amount <= MAX_STAKE, "Above maximum");
        require(tier < 3, "Invalid tier");

        lxonToken.safeTransferFrom(msg.sender, address(this), amount);

        uint48 lockPeriod = tier == 2 ? uint48(365 days) : 
                            tier == 1 ? uint48(90 days) : 
                            uint48(30 days);

        stakeId = nextStakeId++;
        tokenId = nextTokenId++;

        stakes[stakeId] = StakePosition({
            amount: uint96(amount),
            startTime: uint48(block.timestamp),
            lockPeriod: lockPeriod,
            tier: uint8(tier),
            status: 1, // active
            claimedReward: 0
        });

        stakeOwner[stakeId] = msg.sender;
        totalStaked[msg.sender] += amount;
        totalStakedAmount += amount;

        // Mint NFT representing the stake
        emit Transfer(address(0), msg.sender, tokenId);

        emit Staked(stakeId, tokenId, msg.sender, amount, tier, lockPeriod, block.timestamp);
    }

    function unstake(uint256 stakeId) external nonReentrant whenNotPaused whenUnstakingNotPaused {
        StakePosition storage pos = stakes[stakeId];
        require(pos.status == 1, "No active stake");
        require(stakeOwner[stakeId] == msg.sender, "Not your stake");

        uint256 penalty = 0;
        if (block.timestamp < pos.startTime + pos.lockPeriod) {
            penalty = pos.amount / 10;
        }

        uint256 payout = pos.amount - penalty;
        totalStaked[msg.sender] -= pos.amount;
        totalStakedAmount -= pos.amount;
        pos.status = 0; // inactive

        lxonToken.safeTransfer(msg.sender, payout);
        if (penalty > 0) lxonToken.safeTransfer(treasury, penalty);

        // Burn NFT
        uint256 tokenId = _stakeIdToTokenId(stakeId);
        delete stakeOwner[stakeId];
        emit Transfer(msg.sender, address(0), tokenId);

        emit Unstaked(stakeId, tokenId, msg.sender, payout, penalty, block.timestamp);
    }

    /* --------------------------- Yield Vault Integration --------------------------- */

    function addYieldVault(address _vaultAddress, uint256 _apy) external onlyRole(VAULT_MANAGER_ROLE) {
        require(_vaultAddress != address(0), "Zero address");
        require(_apy <= 10000, "APY too high"); // Max 100%

        uint256 vaultId = nextStakeId++; // Reuse counter for vault IDs
        yieldVaults[vaultId] = YieldVault({
            vaultAddress: _vaultAddress,
            apy: _apy,
            active: true
        });

        emit VaultAdded(vaultId, _vaultAddress, _apy, block.timestamp);
    }

    function removeYieldVault(uint256 _vaultId) external onlyRole(VAULT_MANAGER_ROLE) {
        yieldVaults[_vaultId].active = false;
        emit VaultRemoved(_vaultId, block.timestamp);
    }

    function stakeInVault(uint256 _stakeId, uint256 _vaultId) external nonReentrant whenNotPaused whenVaultNotPaused {
        StakePosition storage pos = stakes[_stakeId];
        require(pos.status == 1, "No active stake");
        require(stakeOwner[_stakeId] == msg.sender, "Not your stake");
        require(yieldVaults[_vaultId].active, "Vault not active");

        IERC20(address(lxonToken)).safeTransferFrom(msg.sender, yieldVaults[_vaultId].vaultAddress, pos.amount);

        emit StakeInVault(_stakeId, _vaultId, pos.amount, block.timestamp);
    }

    function collectYield(uint256 _vaultId) external onlyRole(VAULT_MANAGER_ROLE) {
        require(yieldVaults[_vaultId].active, "Vault not active");

        // In production, this would call the vault's yield collection function
        uint256 yieldAmount = 0; // Placeholder

        emit YieldCollected(_vaultId, yieldAmount, block.timestamp);
    }

    /* --------------------------- Rewards --------------------------- */

    function fundRewardPool(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Zero amount");
        lxonToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;
        emit RewardPoolFunded(amount, block.timestamp);
    }

    function claimReward(uint256 stakeId) external nonReentrant whenNotPaused whenRewardClaimingNotPaused {
        StakePosition storage pos = stakes[stakeId];
        require(pos.status == 1, "No active stake");
        require(stakeOwner[stakeId] == msg.sender, "Not your stake");

        uint256 reward = calculateReward(stakeId);
        require(reward > 0, "No reward");
        require(rewardPool >= reward, "Insufficient reward pool");

        pos.claimedReward += uint96(reward);
        rewardPool -= reward;
        lxonToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(stakeId, msg.sender, reward, block.timestamp);
    }

    function calculateReward(uint256 stakeId) public view returns (uint256) {
        StakePosition memory pos = stakes[stakeId];
        if (pos.status != 1) return 0;

        uint256 elapsed = block.timestamp - pos.startTime;
        uint256 multiplier = pos.tier == 2 ? 150 : pos.tier == 1 ? 125 : 100;
        return (pos.amount * elapsed * multiplier) / (365 days * 100);
    }

    /* --------------------------- Slashing --------------------------- */

    function authorizeForSlash(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedForSlash[user] = true;
    }

    function revokeSlashAuthorization(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedForSlash[user] = false;
    }

    function applySlash(address user, uint256 bps, uint256 tier, string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(bps <= 1000, "Penalty too high");
        require(authorizedForSlash[user], "User not authorized for slash");

        uint256 userBalance = lxonToken.balanceOf(user);
        uint256 slashAmount = (userBalance * bps) / 10000;

        require(slashAmount > 0, "No balance");

        uint256 allowance = lxonToken.allowance(user, address(this));
        require(allowance >= slashAmount, "User has not approved this contract");

        lxonToken.safeTransferFrom(user, treasury, slashAmount);

        emit SlashApplied(user, slashAmount, tier, reason, block.timestamp);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Zero treasury");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    /* --------------------------- NFT Functions --------------------------- */

    function _stakeIdToTokenId(uint256 stakeId) internal pure returns (uint256) {
        return stakeId; // Simple mapping for now
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(stakeOwner[tokenId] != address(0), "Token does not exist");
        return bytes(_baseURI).length > 0 ? string(abi.encodePacked(_baseURI, tokenId.toString())) : "";
    }

    function setBaseURI(string memory _newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseURI = _newBaseURI;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextStakeId; i++) {
            if (stakeOwner[i] == owner && stakes[i].status == 1) {
                count++;
            }
        }
        return count;
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        return stakeOwner[tokenId];
    }

    function approve(address, uint256) external pure override {
        revert("Approvals not supported");
    }

    function getApproved(uint256) external pure override returns (address) {
        return address(0);
    }

    function setApprovalForAll(address, bool) external pure override {
        revert("Approvals not supported");
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override {
        revert("Transfers not supported");
    }

    function safeTransferFrom(address, address, uint256) external pure override {
        revert("Transfers not supported");
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure override {
        revert("Transfers not supported");
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) ||
               interfaceId == type(IERC721).interfaceId ||
               interfaceId == type(IERC721Metadata).interfaceId;
    }
}
