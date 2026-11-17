// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * RevenueSplitter
 * ---------------
 * Routes every unit of protocol revenue into one of four buckets:
 *
 *   1. Buyback & burn  (default 40%)  → LXONBuybackVault.buyback()
 *   2. Staker rewards  (default 30%)  → StakingRewards.deposit()
 *   3. Ecosystem       (default 20%)  → EcosystemTreasury
 *   4. Ops/foundation  (default 10%)  → OpsTreasury
 *
 * Callers (feeds, access contracts, POS, marketplaces) call:
 *
 *   IERC20(lxon).approve(splitter, amount);
 *   splitter.deposit(amount, "helio-pos");
 *
 * The splitter emits a Deposited event per source. Governance can retune
 * the bps allocations but can never send funds outside the four whitelisted
 * destinations.
 */
contract RevenueSplitter is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;

    address public buybackVault;
    address public stakingRewards;
    address public ecosystemTreasury;
    address public opsTreasury;

    uint16 public buybackBps  = 4000; // 40%
    uint16 public stakerBps   = 3000; // 30%
    uint16 public ecosystemBps= 2000; // 20%
    uint16 public opsBps      = 1000; // 10%

    uint256 public totalReceived;
    mapping(string => uint256) public receivedBySource;

    event Deposited(
        address indexed from,
        uint256 amount,
        string source,
        uint256 toBuyback,
        uint256 toStakers,
        uint256 toEcosystem,
        uint256 toOps
    );
    event SplitUpdated(uint16 buybackBps, uint16 stakerBps, uint16 ecosystemBps, uint16 opsBps);
    event DestinationUpdated(string which, address newAddr);

    error NotSplitter();
    error BadBps();
    error ZeroAmount();
    error NotConfigured();

    constructor(
        address _lxon,
        address _buybackVault,
        address _stakingRewards,
        address _ecosystemTreasury,
        address _opsTreasury
    ) Ownable(msg.sender) {
        if (_lxon == address(0)) revert NotConfigured();
        lxon = IERC20(_lxon);
        buybackVault = _buybackVault;
        stakingRewards = _stakingRewards;
        ecosystemTreasury = _ecosystemTreasury;
        opsTreasury = _opsTreasury;
    }

    /// @notice Accept LXON revenue and route it according to current bps.
    function deposit(uint256 amount, string calldata source) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (buybackVault == address(0) || stakingRewards == address(0) ||
            ecosystemTreasury == address(0) || opsTreasury == address(0)) revert NotConfigured();

        lxon.safeTransferFrom(msg.sender, address(this), amount);

        uint256 toBuyback   = (amount * buybackBps)   / 10_000;
        uint256 toStakers   = (amount * stakerBps)    / 10_000;
        uint256 toEcosystem = (amount * ecosystemBps) / 10_000;
        uint256 toOps       = amount - toBuyback - toStakers - toEcosystem; // remainder (no dust)

        if (toBuyback   > 0) lxon.safeTransfer(buybackVault,     toBuyback);
        if (toStakers   > 0) lxon.safeTransfer(stakingRewards,   toStakers);
        if (toEcosystem > 0) lxon.safeTransfer(ecosystemTreasury, toEcosystem);
        if (toOps       > 0) lxon.safeTransfer(opsTreasury,       toOps);

        totalReceived += amount;
        receivedBySource[source] += amount;

        emit Deposited(msg.sender, amount, source, toBuyback, toStakers, toEcosystem, toOps);
    }

    /// @notice Governance-only: tune allocations. Must sum to 10,000 bps.
    function setSplit(uint16 _buyback, uint16 _staker, uint16 _ecosystem, uint16 _ops) external onlyOwner {
        if (uint256(_buyback) + _staker + _ecosystem + _ops != 10_000) revert BadBps();
        buybackBps   = _buyback;
        stakerBps    = _staker;
        ecosystemBps = _ecosystem;
        opsBps       = _ops;
        emit SplitUpdated(_buyback, _staker, _ecosystem, _ops);
    }

    function setDestinations(
        address _buyback,
        address _staking,
        address _ecosystem,
        address _ops
    ) external onlyOwner {
        buybackVault      = _buyback;
        stakingRewards    = _staking;
        ecosystemTreasury = _ecosystem;
        opsTreasury       = _ops;
        emit DestinationUpdated("buyback", _buyback);
        emit DestinationUpdated("staking", _staking);
        emit DestinationUpdated("ecosystem", _ecosystem);
        emit DestinationUpdated("ops", _ops);
    }

    /// @notice Read-only view: current split.
    function split() external view returns (uint16, uint16, uint16, uint16) {
        return (buybackBps, stakerBps, ecosystemBps, opsBps);
    }
}
