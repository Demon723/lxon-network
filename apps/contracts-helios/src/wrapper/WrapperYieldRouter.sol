// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IStakingRewards {
    function deposit(uint256 amount) external;
}

/**
 * WrapperYieldRouter
 * ------------------
 * The wrapped asset is *yield-bearing*. Deposits into a lending pool or
 * staking contract. Yield flows back to wrapped-asset holders.
 *
 * For v1: the yield comes from LXON's RevenueSplitter (30% staker share).
 * Each wrapped-asset holder earns pro-rata based on their holding.
 */
contract WrapperYieldRouter is Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable wrappedAsset;
    IERC20 public immutable yieldToken;      // LXON
    address public yieldSource;              // RevenueSplitter

    mapping(address => uint256) public lastClaimedIndex;
    uint256 public accYieldPerToken;         // 1e18 scale
    uint256 public totalYieldDistributed;

    event YieldDeposited(uint256 amount);
    event YieldClaimed(address indexed who, uint256 amount);

    constructor(address _wrapped, address _yield, address _source) Ownable(msg.sender) {
        wrappedAsset = IERC20(_wrapped);
        yieldToken = IERC20(_yield);
        yieldSource = _source;
    }

    /// @notice Called by RevenueSplitter (or a relayer) to push yield in.
    function depositYield(uint256 amount) external {
        require(msg.sender == yieldSource || msg.sender == owner(), "not authorized");
        uint256 supply = wrappedAsset.totalSupply();
        if (supply == 0) {
            yieldToken.safeTransferFrom(msg.sender, address(this), amount);
            return; // hold unallocated
        }
        yieldToken.safeTransferFrom(msg.sender, address(this), amount);
        accYieldPerToken += (amount * 1e18) / supply;
        totalYieldDistributed += amount;
        emit YieldDeposited(amount);
    }

    function claimable(address who) public view returns (uint256) {
        uint256 bal = wrappedAsset.balanceOf(who);
        uint256 accumulated = (bal * accYieldPerToken) / 1e18;
        return accumulated - lastClaimedIndex[who];
    }

    function claim() external {
        uint256 amount = claimable(msg.sender);
        require(amount > 0, "nothing to claim");
        lastClaimedIndex[msg.sender] += amount;
        yieldToken.safeTransfer(msg.sender, amount);
        emit YieldClaimed(msg.sender, amount);
    }
}
