// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * PairSecure -- the V2-shaped pool with `swap()` closed properly, written to be DEPLOYED, not to
 * repair the file that describes what is already on chain.
 *
 * WHY A NEW FILE. `Pair.sol` is the source of record for the live 724 pools, defects included, and
 * that is a deliberate convention in this repo (see docs/runbooks/router-secure-724.md: Router.sol
 * and LXONWrapper.sol are left un-patched for the same reason). Editing a deployed contract's
 * source in place makes the repository safer than the chain -- the next reader of `Pair.sol`
 * assumes the drain is fixed when the bytecode still has it. So the fix lives here, next to the
 * `RouterSecure` it is meant to be used with, and `test/PairLiveShape.t.sol` keeps the defect
 * pinned and reproducible against the real deployed shape.
 *
 * WHAT CHANGED vs the live `Pair.sol` -- two inside `swap()`, one inside `burn()`:
 *   1. an input check. The live version computes amount0In/amount1In and then never requires that
 *      one of them is positive, so a caller can withdraw output without paying anything in --
 *      `test_UnfundedClaim_DrainIsRejected`, and the fuzz case that found it.
 *   2. the invariant. The live version compares a bare product `(reserve0 - out) * (reserve1 - out)`
 *      instead of the fee-adjusted balances against the pre-trade product, so the K check is an
 *      identity for exactly the unfunded single-leg claim it should be refusing.
 *   3. the burn() reserve sync. `_sync()` ran BEFORE the two payouts, so it recorded the balances
 *      the pool held before it paid and left both reserves overstated by amount0/amount1. Moved
 *      after the transfers, matching mint() and swap(). The overstatement let the pool refuse a
 *      deposit up to its own size (`_getAmounts()` saw zero input), under-credit the next LP, and
 *      quote swap output it no longer held -- `test_Burn_ReservesEqualBalancesAfterPayout` and
 *      `test_Burn_ThenRedepositWithdrawnAmounts_MintsAgain`.
 * The input is measured against the SYNCED RESERVES (the deposit arrives before `swap()` is called),
 * which is what makes a legitimate trade pass -- see test_Control_FundedSwap_StillSucceeds.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PairSecure is IERC20, ReentrancyGuard {
    address public token0;
    address public token1;
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public constant MINIMUM_LIQUIDITY = 1;

    IERC20 public token0Contract;
    IERC20 public token1Contract;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    string public constant name = "LP Token";
    string public constant symbol = "LP";
    uint8 public constant decimals = 18;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint256 reserve0, uint256 reserve1);

    constructor(address _token0, address _token1) {
        require(_token0 != _token1, "Pair: IDENTICAL_ADDRESSES");
        token0 = _token0;
        token1 = _token1;
        token0Contract = IERC20(_token0);
        token1Contract = IERC20(_token1);
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function allowance(address owner_, address spender) external view returns (uint256) { return _allowances[owner_][spender]; }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "Pair: transfer amount exceeds allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint256 amount0, uint256 amount1) = _getAmounts();
        
        // If reserves are 0 but pair has balances, use current balances as amounts
        if (reserve0 == 0 && reserve1 == 0) {
            amount0 = token0Contract.balanceOf(address(this));
            amount1 = token1Contract.balanceOf(address(this));
        }
        
        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_AMOUNT");

        uint256 _supply = _totalSupply;
        if (_supply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = _min((amount0 * _supply) / reserve0, (amount1 * _supply) / reserve1);
        }
        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");

        _update();
        _mint(to, liquidity);
        emit Mint(msg.sender, amount0, amount1);
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockNumber) {
        return (uint112(reserve0), uint112(reserve1), uint32(block.timestamp));
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Pair: INSUFFICIENT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Pair: INSUFFICIENT_LIQUIDITY");
        amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Pair: INSUFFICIENT_OUTPUT_AMOUNT");
        if (amount0Out > 0) require(amount0Out < reserve0, "Pair: INSUFFICIENT_LIQUIDITY");
        if (amount1Out > 0) require(amount1Out < reserve1, "Pair: INSUFFICIENT_LIQUIDITY");

        if (amount0Out > 0) token0Contract.transfer(to, amount0Out);
        if (amount1Out > 0) token1Contract.transfer(to, amount1Out);

        uint256 balance0After = token0Contract.balanceOf(address(this));
        uint256 balance1After = token1Contract.balanceOf(address(this));

        // The input is measured against the SYNCED RESERVES, not against the balances read at the
        // top of this function. A trader pays by transferring to the pair BEFORE calling swap(), so
        // the balances here already contain their payment; measuring against balanceBefore would
        // find zero input on every legitimate trade. (That mistake, made while writing this fix, is
        // caught by test_Control_FundedSwap_StillSucceeds and the two router swap tests.)
        uint256 amount0In = balance0After + amount0Out > reserve0 ? balance0After + amount0Out - reserve0 : 0;
        uint256 amount1In = balance1After + amount1Out > reserve1 ? balance1After + amount1Out - reserve1 : 0;

        // FIX 1 (the drain): a swap has to pay something in. Without this, an unfunded single-leg
        // claim made both sides of the old K test algebraically EQUAL — with amount1Out = 0 and no
        // input it reduced to `balance0After * reserve1 >= (reserve0 - amount0Out) * reserve1`,
        // which holds for every amount0Out < reserve0. One call then moved the whole leg out, and
        // the chain's public RPC accepts eth_sendRawTransaction, so any funded address could try.
        require(amount0In > 0 || amount1In > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");

        // FIX 2: the invariant is compared with the PRE-TRADE reserves, with the 0.30% fee taken off
        // the balances that received the input. This is what makes a funded-but-greedy claim revert:
        // the old form only ever bounded the claim by `reserve`, never by the curve.
        uint256 balance0Adjusted = balance0After * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1After * 1000 - amount1In * 3;
        require(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1_000_000, "Pair: K");

        _update();
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 _supply = _totalSupply;
        uint256 liquidity = _balances[msg.sender];
        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_BURNED");

        amount0 = (liquidity * reserve0) / _supply;
        amount1 = (liquidity * reserve1) / _supply;
        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(msg.sender, liquidity);

        token0Contract.transfer(to, amount0);
        token1Contract.transfer(to, amount1);

        // FIX 3 (the reserve desync): sync AFTER the payouts, not before. `_sync()` reads
        // `balanceOf(address(this))`, so running it above the two transfers recorded the balances
        // the pool held BEFORE it paid -- leaving both reserves overstated by exactly
        // amount0/amount1. mint() and swap() already `_update()` after their transfers; burn() was
        // the only path that did not, and the overstatement is not cosmetic:
        //   * `_getAmounts()` computes `balance - reserve`, so a deposit up to the size of the
        //     overstatement registers as zero input and is refused with INSUFFICIENT_AMOUNT --
        //     the pool cannot be refilled to its own prior size (test_Burn_ThenRedepositWithdrawnAmounts_MintsAgain).
        //   * `mint()` divides by reserve, so the next LP is under-credited for the same deposit.
        //   * `swap()` bounds the claim by `reserve`, so it can quote output the pool no longer holds.
        // Asserted as reserve == balance, never as a remembered number: test_Burn_ReservesEqualBalancesAfterPayout.
        _sync();

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function _update() internal {
        reserve0 = token0Contract.balanceOf(address(this));
        reserve1 = token1Contract.balanceOf(address(this));
        emit Sync(reserve0, reserve1);
    }
    
    function forceSync() external {
        _update();
    }
    
    function sync() external {
        _update();
    }

    function _sync() internal { _update(); }

    function _mint(address to, uint256 value) internal {
        _totalSupply += value;
        _balances[to] += value;
        emit Transfer(address(0), to, value);
    }
    function _burn(address from, uint256 value) internal {
        _balances[from] -= value;
        _totalSupply -= value;
        emit Transfer(from, address(0), value);
    }
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "Pair: zero address");
        require(_balances[from] >= amount, "Pair: insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0) && spender != address(0), "Pair: zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y / 2; while (x < z) { z = x; x = (y / x + x) / 2; } }
        else if (y != 0) { z = 1; }
    }
    function _min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }

    function _getAmounts() internal returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = token0Contract.balanceOf(address(this));
        uint256 balance1 = token1Contract.balanceOf(address(this));
        amount0 = balance0 > reserve0 ? balance0 - reserve0 : 0;
        amount1 = balance1 > reserve1 ? balance1 - reserve1 : 0;
    }
}
