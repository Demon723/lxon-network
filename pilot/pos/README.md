# Helios Satellite POS — Pilot Playbook

**Goal**: 10 POS terminals, 3 merchants, 4 weeks, 100+ transactions,
< 5% failure rate, < 30 min settlement.

**Why**: This is the single most defensible, photographable proof that
LXON is real. No other L1 can copy it quickly because it requires the
full stack you've already built (PQ crypto + satellite + NFC + on-chain
settlement).

## Timeline

| Week | Milestone |
|------|-----------|
| 1 | Finalize PCB, order 10 units |
| 2 | Flash firmware, bench test with card simulator |
| 3 | Devnet integration, gateway config |
| 4 | **Deploy to 3 merchants, staff training** |
| 5-7 | Live pilot, daily metrics |
| 8 | Publish report + video |

## Success criteria

| Metric | Target |
|--------|--------|
| Merchants live | 3 |
| POS terminals deployed | 10 |
| Transactions | 100+ |
| Failure rate | < 5% |
| Median settlement time | < 30 min |
| Merchant NPS | > 8/10 |
| Uptime | > 95% |

## Target regions

**Primary**: Rural Kenya (Nairobi + 2 hours out)
- Strong mobile-money culture (M-Pesa)
- English-speaking
- Iridium coverage excellent

**Backup**: Rural Indonesia (Bali + Lombok)
- Large unbanked population
- Tourism = high transaction volume
- Astrocast coverage

## Merchant profile

Ideal pilot merchant:
- 20-200 transactions/day
- Already uses mobile money (M-Pesa, GoPay)
- Owner-operated (fast decisions)
- Sells to end consumers (not B2B)
- Has ~2 hours/week for training

Examples: coffee shops, market stalls, kiosks, small restaurants,
tourist shops, agricultural cooperatives.

## Documents in this folder

| File | Purpose |
|------|---------|
| `merchant-onboarding.md` | Step-by-step merchant recruitment |
| `staff-training.md` | Training curriculum + script |
| `metrics.md` | Daily metrics + dashboard spec |
| `press-release.md` | Draft announcement |
| `video-script.md` | 60-second pilot video script |
| `merchant-kit/` | Handouts, signage, FAQ |
| `scripts/` | Deploy + monitor scripts |