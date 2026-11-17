# TGE Readiness

## Tokenomics model

### Supply

| Allocation | % | Vesting |
|------------|---|---------|
| Community (airdrop + incentives) | 35% | 4y linear, 6mo cliff |
| Ecosystem & R&D | 20% | 4y linear, 6mo cliff |
| Core contributors | 15% | 4y linear, 12mo cliff |
| Early backers | 15% | 4y linear, 12mo cliff |
| Foundation treasury | 10% | 4y linear |
| Protocol liquidity | 5% | Unlocked at TGE |

**Total supply**: 1,000,000,000 LXON (1B, 6 decimals)

**No inflation beyond staking rewards**, and staking rewards taper to zero
as fee revenue grows (Phase 4).

### Value accrual

Every unit of protocol revenue splits four ways:

| Bucket | Default | Purpose |
|--------|---------|---------|
| Buyback & burn | 40% | Deflationary pressure |
| Staker rewards | 30% | Real yield to LXON stakers |
| Ecosystem treasury | 20% | Grants, partnerships, audits |
| Ops / foundation | 10% | Salaries, legal, infra |

Governance can retune these (must sum to 100%). Destinations are immutable
contracts; the splitter can never send funds to an arbitrary address.

### Revenue sources

| Source | Contract | Feeds |
|--------|----------|-------|
| Tx base + priority fees | Chain RPC | `RevenueSplitter.deposit(amount, "tx-fees")` |
| Helios card issuance | `HeliosSatellitePay` | `RevenueSplitter.deposit(amount, "helios-issue")` |
| Helios tap-to-pay | `HeliosSatellitePay` | `RevenueSplitter.deposit(amount, "helios-pos")` |
| Satellite bandwidth | `SatelliteAccess` | `RevenueSplitter.deposit(amount, "sat-bandwidth")` |
| Satellite data market | `OrbitDataMarket` | `RevenueSplitter.deposit(amount, "sat-data")` |
| Enterprise PQ wraps | `EnterpriseWrapping` | `RevenueSplitter.deposit(amount, "enterprise")` |

## Buyback math

If LXON trades at $1 and the chain does $10M/yr in fees:

- $4M/yr → buyback → burns ~4M LXON/yr
- With a 1B supply, that's ~0.4% annual deflation

The lever is **usage**. Every new dApp, POS terminal, and enterprise client
is a source of automatic buy pressure.

## Vesting schedule

```
Community (35%)      ████████████████████████████████████░░░░  4y linear, 6mo cliff
Ecosystem (20%)      ████████████████████░░░░░░░░░░░░░░░░░░  4y linear, 6mo cliff
Core (15%)           ████████████████░░░░░░░░░░░░░░░░░░░░░░  4y linear, 12mo cliff
Early backers (15%)  ████████████████░░░░░░░░░░░░░░░░░░░░░░  4y linear, 12mo cliff
Foundation (10%)     ██████████░░░░░░░░░░░░░░░░░░░░░░░░░░  4y linear
Liquidity (5%)       █████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Unlocked at TGE
```

## Community round

- **Amount**: 350M LXON (35% of supply)
- **Price**: $0.10/LXON (cap: $35M)
- ** vesting**: 4y linear, 6mo cliff
- **Sybil resistance**: on-chain activity only — no invites, no off-chain tasks
- **Points conversion**: 1 point = 1 LXON at TGE (points program runs pre-TGE)

## Governance

Token holders vote on:
- Split retuning (bps)
- New revenue sources (whitelist)
- Grant approvals > $50k
- Protocol upgrades (UUPS via TimelockController, 48h)

Voting power: 1 LXON = 1 vote, with time-lock multiplier (up to 4× for 4-year lock).

## Bootstrapping

Before TGE, run a **points program** that converts to LXON at launch:
- Testnet usage: 1 point / 100 tx
- POS pilot merchant: 100 points / week
- Validator: 50 points / day
- Grants recipient: 500 points / milestone

Points are non-transferable. Sybil resistance: on-chain activity only,
no invites, no off-chain tasks.