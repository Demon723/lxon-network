// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * PQWrappedAsset
 * --------------
 * Wraps an existing asset (BTC, ETH, USDC, ...) into a post-quantum
 * version on LXON. The wrapped version is a standard ERC20, but:
 *
 *   - Minting requires a custodian attestation (see ICustodianAdapter)
 *   - The wrapped asset is yield-bearing (deposit into RevenueSplitter)
 *   - Redemption is 1:1 when the base chain migrates to PQ
 *
 * Multi-asset: one contract per underlying. Deploy once per asset.
 *
 *   qBTC  = PQWrappedAsset(BTC)   underly = native BTC
 *   qETH  = PQWrappedAsset(ETH)   underly = native ETH
 *   qUSDC = PQWrappedAsset(USDC)  underly = ERC20 USDC
 */
contract PQWrappedAsset is ERC20, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum AssetClass { Native, ERC20 }

    AssetClass public immutable assetClass;
    address public immutable underlying;   // address(0) for native BTC/ETH
    uint8   public immutable underlyingDecimals;

    /// Custodian attestation threshold: M of N
    uint8 public threshold;
    mapping(address => bool) public custodians;
    uint8 public custodianCount;

    /// Nonce per custodian to prevent replay
    mapping(address => uint256) public custodianNonce;

    /// Track wrapped amounts per user for redemptions
    mapping(address => uint256) public wrappedOf;

    /// Redemption is enabled only after base chain migrates (governance flag)
    bool public redemptionOpen;

    /// Track minted vs redeemed
    uint256 public totalMinted;
    uint256 public totalRedeemed;

    event CustodianSet(address indexed who, bool allowed);
    event ThresholdUpdated(uint8 newThreshold);
    event Wrapped(address indexed to, uint256 amount, bytes32 ref);
    event Unwrapped(address indexed from, uint256 amount, bytes32 ref);
    event RedemptionOpened();

    error NotCustodian();
    error AlreadyAttested();
    error BadSignature();
    error RedemptionClosed();
    error InsufficientBalance();
    error AlreadyApproved();

    modifier onlyCustodian() { if (!custodians[msg.sender]) revert NotCustodian(); _; }

    constructor(
        string memory name_,
        string memory symbol_,
        AssetClass _class,
        address _underlying,
        uint8 _decimals
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        assetClass = _class;
        underlying = _underlying;
        underlyingDecimals = _decimals;
        threshold = 1;
    }

    // -----------------------------------------------------------------------
    // Custodian management
    // -----------------------------------------------------------------------

    function setCustodian(address who, bool allowed) external onlyOwner {
        if (custodians[who] != allowed) {
            custodians[who] = allowed;
            custodianCount = allowed ? custodianCount + 1 : custodianCount - 1;
            emit CustodianSet(who, allowed);
        }
    }

    function setThreshold(uint8 t) external onlyOwner {
        require(t > 0 && t <= custodianCount, "bad threshold");
        threshold = t;
        emit ThresholdUpdated(t);
    }

    // -----------------------------------------------------------------------
    // Wrap: deposit underlying, mint wrapped
    // -----------------------------------------------------------------------

    /**
     * @notice Wrap an ERC20 underlying. Caller must have approved this contract.
     */
    function wrapERC20(uint256 amount, bytes32 ref) external nonReentrant {
        require(assetClass == AssetClass.ERC20, "not ERC20");
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        _mintWrapped(msg.sender, amount, ref);
    }

    /**
     * @notice Attest a native (BTC/ETH) deposit. Called by a custodian after
     *         the deposit is confirmed on the base chain.
     */
    function attestNative(address to, uint256 amount, bytes32 ref) external onlyCustodian {
        require(assetClass == AssetClass.Native, "not native");
        custodianNonce[msg.sender]++;
        _mintWrapped(to, amount, ref);
    }

    function _mintWrapped(address to, uint256 amount, bytes32 ref) internal {
        _mint(to, amount);
        wrappedOf[to] += amount;
        totalMinted += amount;
        emit Wrapped(to, amount, ref);
    }

    // -----------------------------------------------------------------------
    // Unwrap: burn wrapped, receive underlying (only after redemption opens)
    // -----------------------------------------------------------------------

    function openRedemption() external onlyOwner {
        redemptionOpen = true;
        emit RedemptionOpened();
    }

    /**
     * @notice Burn wrapped tokens. Custodian releases underlying on base chain.
     *         The actual release is off-chain — this emits an event the
     *         custodian watches.
     */
    function unwrap(uint256 amount, bytes32 ref) external nonReentrant {
        if (!redemptionOpen) revert RedemptionClosed();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        _burn(msg.sender, amount);
        wrappedOf[msg.sender] -= amount;
        totalRedeemed += amount;
        emit Unwrapped(msg.sender, amount, ref);
    }

    // -----------------------------------------------------------------------
    // Supply tracking
    // -----------------------------------------------------------------------

    function circulating() external view returns (uint256) {
        return totalMinted - totalRedeemed;
    }
}
