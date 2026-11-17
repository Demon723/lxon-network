// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LxonRedemption
 * @notice Allows LXON holders to redeem for USDC via the Peg Stability Module.
 *         Also supports routing redemption proceeds to an off-ramp custodian.
 */
contract LxonRedemption is Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;
    IERC20 public immutable usdc;
    address public psm;

    // Off-ramp custodian integration
    address public custodianWallet;
    mapping(address => bool) public authorizedOperators;

    // Redemption tracking
    struct RedemptionRequest {
        address user;
        uint256 lxonAmount;
        uint256 usdcAmount;
        uint256 timestamp;
        bool fulfilled;
    }

    mapping(bytes32 => RedemptionRequest) public redemptionRequests;
    mapping(address => bytes32[]) public userRedemptions;

    // Fee (in basis points)
    uint256 public redemptionFeeBps = 10; // 0.10%
    uint256 public constant MAX_FEE_BPS = 100; // 1.00%

    event RedemptionInitiated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 lxonAmount,
        uint256 usdcAmount
    );

    event RedemptionFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        uint256 usdcAmount
    );

    event OffRampInitiated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 lxonAmount,
        address custodian
    );

    modifier onlyOperator() {
        require(authorizedOperators[msg.sender] || msg.sender == owner(), "NOT_OPERATOR");
        _;
    }

    constructor(
        address _lxon,
        address _usdc,
        address _psm,
        address _custodianWallet,
        address _owner
    ) Ownable(_owner) {
        require(_lxon != address(0), "ZERO_LXON");
        require(_usdc != address(0), "ZERO_USDC");
        // Allow zero PSM initially - will be set later
        lxon = IERC20(_lxon);
        usdc = IERC20(_usdc);
        psm = _psm;
        custodianWallet = _custodianWallet;
    }

    // ============ ON-CHAIN REDEMPTION (LXON → USDC) ============

    /**
     * @notice Redeem LXON for USDC via the PSM.
     * @param lxonAmount Amount of LXON to redeem (18 decimals).
     * @return usdcReceived Amount of USDC received (6 decimals).
     */
    function redeemForUSDC(uint256 lxonAmount)
        external
        whenNotPaused
        returns (uint256 usdcReceived)
    {
        require(lxonAmount > 0, "ZERO_AMOUNT");

        // Calculate fee
        uint256 fee = (lxonAmount * redemptionFeeBps) / 10_000;
        uint256 netLxon = lxonAmount - fee;

        // Transfer LXON from user to this contract
        lxon.safeTransferFrom(msg.sender, address(this), lxonAmount);

        // Approve PSM to burn the LXON
        lxon.forceApprove(psm, netLxon);

        // Call PSM.redeem(lxonAmount) — PSM burns LXON and sends USDC back
        (bool success, bytes memory data) = psm.call(
            abi.encodeWithSignature("redeem(uint256)", netLxon)
        );
        require(success, "PSM_REDEEM_FAILED");

        usdcReceived = abi.decode(data, (uint256));

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, usdcReceived);

        // Generate request ID
        bytes32 requestId = keccak256(abi.encodePacked(
            msg.sender, lxonAmount, block.timestamp, block.number
        ));

        redemptionRequests[requestId] = RedemptionRequest({
            user: msg.sender,
            lxonAmount: lxonAmount,
            usdcAmount: usdcReceived,
            timestamp: block.timestamp,
            fulfilled: true
        });
        userRedemptions[msg.sender].push(requestId);

        emit RedemptionInitiated(requestId, msg.sender, lxonAmount, usdcReceived);
        emit RedemptionFulfilled(requestId, msg.sender, usdcReceived);
    }

    // ============ OFF-RAMP TO BANK (LXON → Custodian → USD) ============

    /**
     * @notice Send LXON to the custodian for fiat off-ramp.
     *         The custodian will wire USD to the user's bank account.
     * @param lxonAmount Amount of LXON to redeem.
     * @param bankReference Off-chain reference for the bank wire (hashed).
     */
    function redeemToBank(uint256 lxonAmount, bytes32 bankReference)
        external
        whenNotPaused
    {
        require(lxonAmount > 0, "ZERO_AMOUNT");
        require(custodianWallet != address(0), "NO_CUSTODIAN");

        // Transfer LXON to custodian
        lxon.safeTransferFrom(msg.sender, custodianWallet, lxonAmount);

        bytes32 requestId = keccak256(abi.encodePacked(
            msg.sender, lxonAmount, bankReference, block.timestamp
        ));

        redemptionRequests[requestId] = RedemptionRequest({
            user: msg.sender,
            lxonAmount: lxonAmount,
            usdcAmount: 0, // Fiat amount is off-chain
            timestamp: block.timestamp,
            fulfilled: false
        });
        userRedemptions[msg.sender].push(requestId);

        emit OffRampInitiated(requestId, msg.sender, lxonAmount, custodianWallet);
    }

    /**
     * @notice Operator marks an off-ramp request as fulfilled after the wire settles.
     */
    function markFulfilled(bytes32 requestId) external onlyOperator {
        RedemptionRequest storage req = redemptionRequests[requestId];
        require(req.user != address(0), "NOT_FOUND");
        require(!req.fulfilled, "ALREADY_FULFILLED");
        req.fulfilled = true;
        emit RedemptionFulfilled(requestId, req.user, req.usdcAmount);
    }

    // ============ ADMIN ============

    function setRedemptionFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        redemptionFeeBps = _feeBps;
    }

    function setPSM(address _psm) external onlyOwner {
        require(_psm != address(0), "ZERO_PSM");
        psm = _psm;
    }

    function setCustodianWallet(address _custodian) external onlyOwner {
        custodianWallet = _custodian;
    }

    function setOperator(address operator, bool allowed) external onlyOwner {
        authorizedOperators[operator] = allowed;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
