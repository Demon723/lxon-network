// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../contracts/WETH.sol";
import {LXON} from "../contracts/LXON.sol";
import {PairSecure} from "../contracts/PairSecure.sol";

/// @title PairSecure (the unfunded-swap regression)
/// @notice The drain that forced the live LXON/USDC* pair (0x710011e5… on chain 724) to be
/// emergency-unwrapped, held as an executable regression suite.
///
/// `Pair.sol` stays exactly as the live pools are -- see docs/runbooks/router-secure-724.md for why
/// this repo does not patch a deployed contract's source in place. The fix is `PairSecure`, and
/// `test/PairLiveShape.t.sol` is the file that shows the hole still open in the deployed shape.
///
/// The unpatched `swap()` tested
///     require(balance0After * balance1After >= (reserve0 - amount0Out) * (reserve1 - amount1Out))
/// When a caller claims one leg and pays in nothing, `amount1Out == 0` and the balances equal the
/// reserves, so both sides collapse to `(reserve0 - amount0Out) * reserve1` — an identity. The check
/// passed for every `amount0Out < reserve0`: one transaction moved the whole leg out, and
/// `rpc.lxon.in` accepts `eth_sendRawTransaction` from anyone, so anyone with gas could try it.
///
/// Every case asserts a property (the pool still holds what it held), never a remembered number.
contract PairSecureTest is Test {
    WETH9 internal weth;
    LXON internal lxon;
    PairSecure internal pair;
    address internal lp = makeAddr("lp");
    address internal attacker = makeAddr("attacker");

    /// Seed sizes mirrored from test/Pair.t.sol so the LXON mint ceiling is not the thing under test.
    /// NOTE the scale: `mint(x)` credits `x * 10_000` token-wei in this contract (the 6-decimal
    /// ceiling applied to an 18-decimal token, measured not assumed), so the mint argument and the
    /// reserve it produces are different numbers. Assertions below use the reserve.
    uint256 internal constant SEED_WETH = 1000 ether;
    uint256 internal constant SCALE = 10_000;
    uint256 internal constant SEED_LXON = 1_000_000 * SCALE; // 10,000,000,000 token-wei

    function setUp() public {
        weth = new WETH9();
        lxon = new LXON(address(this));
        pair = new PairSecure(address(weth), address(lxon));

        lxon.grantRole(bytes32(0), address(this));
        lxon.grantRole(bytes32(uint256(keccak256("MINT_ROLE"))), address(this));
        lxon.grantRole(bytes32(uint256(keccak256("ORACLE_ROLE"))), address(this));
        lxon.updateCeiling(1_000_000_000_000, bytes32(0));

        _mintLxon(address(pair), SEED_LXON);
        weth.deposit{value: SEED_WETH}(address(pair));
        pair.mint(lp);

        assertEq(pair.reserve0(), SEED_WETH, "seed: reserve0");
        assertEq(pair.reserve1(), SEED_LXON, "seed: reserve1");
    }

    /// @dev mint in token-wei, converting through the contract's own scale; refuses a non-exact ask
    /// so a rounding surprise cannot quietly change what a test actually seeded.
    function _mintLxon(address to, uint256 tokenWei) internal {
        require(tokenWei % SCALE == 0, "test: mint ask is not a whole number of mint units");
        lxon.mint(to, tokenWei / SCALE, bytes32(0));
        require(lxon.balanceOf(to) >= tokenWei, "test: mint did not credit the expected tokens");
    }

    // ------------------------------------------------------------- the regression
    /// @notice An unfunded single-leg claim is rejected, and the pool keeps every wei.
    function test_UnfundedClaim_DrainIsRejected() public {
        vm.prank(attacker);
        vm.expectRevert("Pair: INSUFFICIENT_INPUT_AMOUNT");
        pair.swap(SEED_WETH - 1, 0, attacker);

        assertEq(weth.balanceOf(address(pair)), SEED_WETH, "not one wei may leave the pool");
        assertEq(weth.balanceOf(attacker), 0, "attacker must receive nothing");
        assertEq(pair.reserve0(), SEED_WETH, "reserves untouched");
    }

    /// @notice Same attack on the other leg — the guard must not be directional.
    function test_UnfundedClaim_DrainIsRejected_OtherLeg() public {
        vm.prank(attacker);
        vm.expectRevert("Pair: INSUFFICIENT_INPUT_AMOUNT");
        pair.swap(0, SEED_LXON - 1, attacker);

        assertEq(lxon.balanceOf(address(pair)), SEED_LXON, "not one wei may leave the pool");
        assertEq(lxon.balanceOf(attacker), 0, "attacker must receive nothing");
    }

    /// @notice Claiming nearly the whole leg via the other token, still with no input.
    function test_UnfundedClaim_NearFullLxonLeg() public {
        vm.prank(attacker);
        vm.expectRevert("Pair: INSUFFICIENT_INPUT_AMOUNT");
        pair.swap(0, SEED_LXON / 2, attacker);
        assertEq(lxon.balanceOf(address(pair)), SEED_LXON, "pool intact");
    }

    // ------------------------------------------------------------- controls
    /// @notice CONTROL 1 — the fix must not break a real trade: pay LXON in at the pool's own quote,
    /// receive WETH out, and both legs move.
    function test_Control_FundedSwap_StillSucceeds() public {
        uint256 amountIn = SEED_LXON / 2;
        _mintLxon(attacker, amountIn);
        uint256 quote = pair.getAmountOut(amountIn, SEED_LXON, SEED_WETH);
        assertTrue(quote > 0, "quote must be positive");

        vm.prank(attacker);
        lxon.transfer(address(pair), amountIn);
        vm.prank(attacker);
        pair.swap(quote, 0, attacker);

        assertEq(weth.balanceOf(attacker), quote, "trader received the quoted WETH");
        assertEq(weth.balanceOf(address(pair)), SEED_WETH - quote, "pool paid it out");
        assertEq(lxon.balanceOf(address(pair)), SEED_LXON + amountIn, "pool received the LXON");
        assertEq(pair.reserve0(), weth.balanceOf(address(pair)), "reserve0 re-synced");
        assertEq(pair.reserve1(), lxon.balanceOf(address(pair)), "reserve1 re-synced");
    }

    /// @notice CONTROL 2 — a funded but greedy claim is refused by the invariant itself, proving the
    /// guard is a real K test and not merely "did you send something".
    function test_Control_FundedButGreedyClaim_RevertedByK() public {
        _mintLxon(attacker, SCALE);
        vm.prank(attacker);
        lxon.transfer(address(pair), SCALE); // one mint unit in
        vm.prank(attacker);
        vm.expectRevert("Pair: K");
        pair.swap(1 ether, 0, attacker); // 0.1% of the WETH leg for one mint unit (1e4 token-wei)
        assertEq(weth.balanceOf(address(pair)), SEED_WETH, "pool intact after the greedy claim");
    }

    /// @notice CONTROL 3 — no output claimed at all is rejected before anything moves.
    function test_Control_EmptyClaim_Rejected() public {
        vm.prank(attacker);
        vm.expectRevert("Pair: INSUFFICIENT_OUTPUT_AMOUNT");
        pair.swap(0, 0, attacker);
    }

    /// @notice The fee boundary is exact: the pool's own quote passes, one wei more fails. Uses a
    /// freshly seeded pair so the first swap cannot leave state that makes the second test pass.
    function test_FeeBoundaryIsExact() public {
        uint256 amountIn = SEED_LXON / 10;
        _mintLxon(attacker, amountIn * 2);
        uint256 quote = pair.getAmountOut(amountIn, SEED_LXON, SEED_WETH);

        vm.prank(attacker);
        lxon.transfer(address(pair), amountIn);
        vm.prank(attacker);
        pair.swap(quote, 0, attacker); // accepted at exactly the invariant's boundary

        PairSecure fresh = PairSecure(_reseeded());
        vm.prank(attacker);
        lxon.transfer(address(fresh), amountIn); // the second half of the pre-minted pair
        vm.prank(attacker);
        vm.expectRevert("Pair: K");
        fresh.swap(quote + 1, 0, attacker);
        assertEq(weth.balanceOf(address(fresh)), SEED_WETH, "fresh pair untouched");
    }

    /// @notice Property over arbitrary claim sizes: an unfunded swap either reverts or changes
    /// nothing. There is no in-between where value leaves.
    function testFuzz_UnfundedClaim_NeverMovesValue(uint128 claim) public {
        vm.assume(claim > 0);
        vm.prank(attacker);
        try pair.swap(claim, 0, attacker) {
            assertEq(weth.balanceOf(address(pair)), SEED_WETH, "no value may leave unfunded");
            assertEq(lxon.balanceOf(address(pair)), SEED_LXON, "no value may leave unfunded");
        } catch {
            assertEq(weth.balanceOf(address(pair)), SEED_WETH, "reverted, so pool intact");
        }
    }

    // ------------------------------------------------------------- burn() reserve sync
    /// @notice burn() must leave the reserves equal to what the pool ACTUALLY holds after paying
    /// out. The desync was `_burn -> _sync() -> transfers`: `_sync()` read the balances before the
    /// two `transfer` calls moved the tokens out, so both reserves stayed overstated by exactly
    /// amount0/amount1. mint() (:101) and swap() (:149) both `_update()` AFTER their transfers;
    /// burn() was the only path that did not.
    ///
    /// Asserts the property (reserve == balance), never a remembered number, so it cannot rot.
    function test_Burn_ReservesEqualBalancesAfterPayout() public {
        uint256 lpBal = pair.balanceOf(lp);
        assertTrue(lpBal > 0, "lp must hold shares to burn");
        // Burn half, so the pool is left with a non-zero balance on both legs and the assertion
        // is not trivially satisfied by an emptied pool.
        vm.prank(lp);
        pair.transfer(attacker, lpBal / 2);

        uint256 wethBefore = weth.balanceOf(address(pair));
        uint256 lxonBefore = lxon.balanceOf(address(pair));

        vm.prank(lp);
        (uint256 amount0, uint256 amount1) = pair.burn(lp);

        assertTrue(amount0 > 0 && amount1 > 0, "burn must pay both legs");
        assertEq(weth.balanceOf(lp), amount0, "lp received the WETH leg");
        assertEq(lxon.balanceOf(lp), amount1, "lp received the LXON leg");
        assertEq(weth.balanceOf(address(pair)), wethBefore - amount0, "pool paid out amount0");
        assertEq(lxon.balanceOf(address(pair)), lxonBefore - amount1, "pool paid out amount1");

        assertEq(pair.reserve0(), weth.balanceOf(address(pair)), "reserve0 == post-payout balance");
        assertEq(pair.reserve1(), lxon.balanceOf(address(pair)), "reserve1 == post-payout balance");
    }

    /// @notice The economic consequence of the desync, and the control that the fix is not merely
    /// cosmetic: after burning half the pool, re-depositing EXACTLY the withdrawn amounts must mint
    /// new LP. With the reserves overstated, `_getAmounts()` computes `balance - reserve == 0` on
    /// both legs and the deposit is refused with INSUFFICIENT_AMOUNT -- the pool cannot be refilled
    /// to its own prior size, and any smaller deposit is refused too.
    function test_Burn_ThenRedepositWithdrawnAmounts_MintsAgain() public {
        uint256 lpBal = pair.balanceOf(lp);
        vm.prank(lp);
        pair.transfer(attacker, lpBal / 2);
        vm.prank(lp);
        (uint256 amount0, uint256 amount1) = pair.burn(lp);

        // Put back precisely what burn() paid out. The LXON leg is an arbitrary wei amount (it is
        // a pro-rata share, not a whole mint unit), so it is transferred from a pre-minted buffer
        // rather than minted -- _mintLxon refuses a non-exact ask by design.
        _mintLxon(address(this), SEED_LXON);
        weth.deposit{value: amount0}(address(pair));
        lxon.transfer(address(pair), amount1);

        uint256 supplyBefore = pair.totalSupply();
        uint256 lpBefore = pair.balanceOf(lp);
        pair.mint(lp);

        assertTrue(pair.balanceOf(lp) > lpBefore, "the re-deposit must credit new LP");
        assertTrue(pair.totalSupply() > supplyBefore, "supply must grow");
        assertEq(pair.reserve0(), weth.balanceOf(address(pair)), "reserve0 synced after the mint");
        assertEq(pair.reserve1(), lxon.balanceOf(address(pair)), "reserve1 synced after the mint");
    }

    function _reseeded() internal returns (address p) {
        p = address(new PairSecure(address(weth), address(lxon)));
        _mintLxon(p, SEED_LXON);
        weth.deposit{value: SEED_WETH}(p);
        PairSecure(p).mint(lp);
    }
}
