# LXON Tokenomics

> **Status of this file — design intent, not on-chain state (annotated 2026-10-29).**
>
> Nothing below this line describes what the deployed token does. Read
> [`listing/ON-CHAIN-FACTS-2026-10-29.md`](./listing/ON-CHAIN-FACTS-2026-10-29.md) for that. The measured
> position, re-read a third time at chain-724 block `0x2c872` (182,392) on 2026-10-29:
>
> - `LXON`, **18 decimals**, `totalSupply()` = **42,700,020,000**, **no cap** (`MAX_SUPPLY` does not appear in
>   the verified source, and a `MAX_SUPPLY()` call reverts — reverting is what an absent getter does, though
>   the revert carries no selector error, so this is an inference from the verified source rather than a
>   proof from the revert. `mint()` is gated only by `MINTER_ROLE`, which the deployer EOA holds).
>   This figure **changed twice while this file was being annotated**: 100,020,000 → 200,020,000 at
>   block 173,297 → 42,700,020,000 at block 176,301.
> - **11 holders with balance, 12 addresses listed**; **99.7658% in the founder EOA** and 0.2102% in the
>   deployer EOA — i.e. two project EOAs hold **99.9760%**. The AMM pair holds 10,001,000 (0.0234%), which
>   is the entire public market for the token. The earlier "89.78% in one EOA, 10.00% in the pair" was
>   true of a 100,020,000 supply and is not true now.
> - **No vesting contract holds any LXON, and nothing is locked.** The 35/20/15/15/10/5 split and every
>   cliff below are unbuilt.
> - **No revenue splitter is deployed**, so the four-way split has nothing feeding it.
> - The listed token **has no `ERC20Votes`**, so "token holders vote" has no mechanism yet.
> - **Six `mint()` events are in the log**: 0.0001 dust at block 44, 99,999,999.9999 at 16,391, then
>   10,000 + 10,000 at blocks 146,396/146,422, then 100,000,000 at 173,297 and **42,500,000,000** at
>   176,301 — all signed by the same minter key, the last two credited to the founder wallet. They sum to
>   `totalSupply()` exactly. "No inflation beyond staking rewards" is not the current behaviour and has
>   not been since 2026-10-27.
> - There is **no market**: one self-dealt pool on a chain no aggregator indexes, and the feed's USD price
>   is a unit substitution (`price.json` × Ethereum's price).
>
> "With a 1B supply" in the buyback math below is a hypothetical about that unbuilt design; the deployed
> figure is 42,700,020,000 — **42.7× that hypothetical** — and the buyback has never run.

## Value Accrual Model

Every unit of protocol revenue splits four ways:

| Bucket | Default | Purpose |
|--------|---------|---------|
| **Buyback & burn** | 40% | Deflationary pressure |
| **Staker rewards** | 30% | Real yield to LXON stakers |
| **Ecosystem treasury** | 20% | Grants, partnerships, audits |
| **Ops / foundation** | 10% | Salaries, legal, infra |

Governance can retune these (must sum to 100%). Destinations are immutable
contracts; the splitter can never send funds to an arbitrary address.

## Revenue sources

| Source | Contract | Feeds |
|--------|----------|-------|
| Tx base + priority fees | Chain RPC | `RevenueSplitter.deposit(amount, "tx-fees")` |
| Helios card issuance | `HeliosSatellitePay` | `RevenueSplitter.deposit(amount, "helios-issue")` |
| Helios tap-to-pay | `HeliosSatellitePay` | `RevenueSplitter.deposit(amount, "helios-pos")` |
| Satellite bandwidth | `SatelliteAccess` | `RevenueSplitter.deposit(amount, "sat-bandwidth")` |
| Satellite data market | `OrbitDataMarket` | `RevenueSplitter.deposit(amount, "sat-data")` |
| Enterprise PQ wraps | `EnterpriseWrapping` | `RevenueSplitter.deposit(amount, "enterprise")` |

## Supply — *planned; no contract enforces any row of this table*

| Allocation | % | Vesting |
|------------|---|---------|
| Community (airdrop + incentives) | 35% | 4y linear, 6mo cliff |
| Ecosystem & R&D | 20% | 4y linear, 6mo cliff |
| Core contributors | 15% | 4y linear, 12mo cliff |
| Early backers | 15% | 4y linear, 12mo cliff |
| Foundation treasury | 10% | 4y linear |
| Protocol liquidity | 5% | Unlocked at TGE |

**No inflation beyond staking rewards**, and staking rewards taper to zero
as fee revenue grows (Phase 4).

## Buyback math

If LXON trades at $1 and the chain does $10M/yr in fees:

- $4M/yr → buyback → burns ~4M LXON/yr
- With a 1B supply, that's ~0.4% annual deflation

The lever is **usage**. Every new dApp, POS terminal, and enterprise client
is a source of automatic buy pressure.

## Bootstrapping

Before TGE, run a **points program** that converts to LXON at launch:
- Testnet usage: 1 point / 100 tx
- POS pilot merchant: 100 points / week
- Validator: 50 points / day
- Grants recipient: 500 points / milestone

Points are non-transferable. Sybil resistance: on-chain activity only,
no invites, no off-chain tasks.

## Governance

Token holders vote on:
- Split retuning (bps)
- New revenue sources (whitelist)
- Grant approvals > $50k
- Protocol upgrades (UUPS via TimelockController, 48h)

Voting power: 1 LXON = 1 vote, with time-lock multiplier (up to 4× for 4-year lock).
