# TGE Readiness Checklist

## Phase 1 — Foundation (T-90 days)

- [ ] Finalize tokenomics model (`pilot/tge/tokenomics.md`)
- [ ] Audit: RevenueSplitter, StakingRewards, LXONBuybackVault
- [ ] Audit: SatelliteSignatureV2 + MlDsaVerifierFactory
- [ ] Deploy testnet: RevenueSplitter + StakingRewards + BuybackVault
- [ ] Deploy testnet: SatelliteSignatureV2 (with precompile probe)
- [ ] Points program smart contract (vesting + conversion)
- [ ] Community airdrop contract (merkle-distributor)

## Phase 2 — Liquidity (T-60 days)

- [ ] DEX pair: LXON/WETH (Uniswap V2 or V3)
- [ ] Initial liquidity: 5% of supply ($5M at $0.10)
- [ ] Market maker agreement (if applicable)
- [ ] CEX listings: 3-5 tier-2 exchanges
- [ ] Bridge: LXON ↔ Ethereum, Base, Arbitrum

## Phase 3 — Community (T-30 days)

- [ ] Points program launch (testnet + POS pilot)
- [ ] Airdrop snapshot (on-chain activity based)
- [ ] Community round registration open
- [ ] Governance forum live
- [ ] Documentation site live
- [ ] Social media: Twitter, Discord, Telegram

## Phase 4 — TGE (T-0)

- [ ] TimelockController deployed (48h delay)
- [ ] UUPS proxies for: RevenueSplitter, StakingRewards, BuybackVault
- [ ] Token contract deployed (ERC20 + permit)
- [ ] Vesting contracts live
- [ ] DEX pair live with initial liquidity
- [ ] CEX listings go live
- [ ] Points → LXON conversion window opens (30 days)

## Phase 5 — Post-TGE (T+30 days)

- [ ] First governance proposal (split retuning)
- [ ] First buyback execution (from tx fees)
- [ ] First staker rewards distributed
- [ ] Community round claims open
- [ ] 90-day execution tracker review

## Risks

| Risk | Mitigation |
|------|------------|
| Low initial liquidity | 5% supply pre-funded, MM agreement |
| Governance attack | Timelock + 48h delay + large holders |
| Buyback insufficient | Multiple revenue sources, governance can retune |
| Regulatory uncertainty | Foundation treasury for legal, compliant structure |
| Satellite latency spikes | Multi-modem redundancy (Iridium + Astrocast) |

## Team allocation

| Role | % of team pool | Vesting |
|------|---------------|---------|
| CEO / Founder | 40% | 4y linear, 12mo cliff |
| CTO / Founder | 30% | 4y linear, 12mo cliff |
| Core engineers | 20% | 4y linear, 12mo cliff |
| Advisors | 10% | 4y linear, 6mo cliff |

Team pool is part of the 15% "Core contributors" allocation.