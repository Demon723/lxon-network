// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * MarketMakerVault
 * ----------------
 * Provides option-based incentives to market makers — NOT free tokens.
 *
 * MMs commit to providing liquidity on a specific venue for a period.
 * In return, they receive a call option on LXON at a strike price.
 * The option vests linearly; if the MM leaves early, they forfeit
 * unvested options.
 *
 * This avoids the "mercenary liquidity" problem where MMs dump free
 * tokens and leave.
 */
contract MarketMakerVault is Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable lxon;

    struct Commitment {
        address mm;
        bytes32 venue;         // keccak256("uniswap-v3-eth" | ...)
        uint256 minLiquidity;  // USD (off-chain verified, attested)
        uint256 optionSize;    // LXON
        uint256 strikeWei;     // price per LXON in wei (USDC)
        uint64  start;
        uint64  end;
        uint256 claimed;
        bool    active;
    }

    mapping(bytes32 => Commitment) public commitments;   // id => Commitment
    mapping(address => bool) public attestors;
    bytes32[] public commitmentIds;

    event CommitmentCreated(bytes32 indexed id, address indexed mm, uint256 optionSize, uint64 end);
    event CommitmentAttested(bytes32 indexed id, uint256 liquidity);
    event OptionClaimed(bytes32 indexed id, uint256 amount);
    event CommitmentCancelled(bytes32 indexed id);

    error NotAttestor();
    error NotActive();
    error NotMM();
    error NothingToClaim();
    error CommitmentNotEnded();

    modifier onlyAttestor() { require(attestors[msg.sender] || msg.sender == owner(), "not attestor"); _; }

    constructor(address _lxon) Ownable(msg.sender) { lxon = IERC20(_lxon); }

    function setAttestor(address who, bool allowed) external onlyOwner { attestors[who] = allowed; }

    function createCommitment(
        bytes32 id,
        address mm,
        bytes32 venue,
        uint256 minLiquidity,
        uint256 optionSize,
        uint256 strikeWei,
        uint64  durationSeconds
    ) external onlyOwner {
        require(commitments[id].mm == address(0), "id exists");
        commitments[id] = Commitment({
            mm: mm, venue: venue, minLiquidity: minLiquidity, optionSize: optionSize,
            strikeWei: strikeWei, start: uint64(block.timestamp),
            end: uint64(block.timestamp) + durationSeconds,
            claimed: 0, active: true
        });
        commitmentIds.push(id);
        emit CommitmentCreated(id, mm, optionSize, uint64(block.timestamp) + durationSeconds);
    }

    function attestLiquidity(bytes32 id) external onlyAttestor {
        Commitment storage c = commitments[id];
        require(c.active, "not active");
        emit CommitmentAttested(id, c.minLiquidity);
    }

    /// @notice MM claims vested option tokens (linear from start to end).
    function claim(bytes32 id) external {
        Commitment storage c = commitments[id];
        if (!c.active) revert NotActive();
        if (msg.sender != c.mm) revert NotMM();

        uint256 elapsed = block.timestamp - c.start;
        uint256 duration = c.end - c.start;
        if (elapsed > duration) elapsed = duration;

        uint256 vested = (c.optionSize * elapsed) / duration;
        uint256 claimable = vested - c.claimed;
        if (claimable == 0) revert NothingToClaim();

        c.claimed += claimable;
        lxon.safeTransfer(c.mm, claimable);
        emit OptionClaimed(id, claimable);
    }

    function cancel(bytes32 id) external onlyOwner {
        Commitment storage c = commitments[id];
        c.active = false;
        emit CommitmentCancelled(id);
    }
}
