# Pilot Metrics

Collect daily. Upload to the pilot dashboard (Google Sheet or LXON internal).

## Daily metrics

| Date | Tx count | Failed tx | Failure % | Settle time (median) | Uptime % | Notes |
|------|----------|-----------|-----------|----------------------|----------|-------|
| W1D1 | | | | | | |
| W1D2 | | | | | | |

## Per-merchant metrics

| Merchant | Location | Tx/day | Failure % | NPS | Notes |
|----------|----------|--------|-----------|-----|-------|
| M1 | | | | | |
| M2 | | | | | |
| M3 | | | | | |

## Weekly aggregate

| Week | Total tx | Failure % | Median settle | Avg uptime | New merchants |
|------|----------|-----------|---------------|------------|---------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |

## Dashboard spec

- Real-time: tx count (rolling 24h), failure rate, median settle time
- Per-merchant drill-down
- Alert: failure rate > 10% for 1 hour → page on-call
- Alert: any merchant down > 2 hours → visit

## Data collection script

```bash
#!/usr/bin/env bash
# scripts/collect-metrics.sh — run nightly on the gateway
set -euo pipefail

OUT=/mnt/pilot/metrics-$(date +%Y-%m-%d).json
curl -s http://gateway:8080/metrics | jq '{
  tx_count: .transactions.total,
  failed: .transactions.failed,
  failure_rate: (.transactions.failed / .transactions.total),
  median_settle_ms: .settlement.median_ms,
  uptime_pct: .uptime.rolling_24h
}' > "$OUT"
echo "wrote $OUT"
```

## Success criteria (target)

| Metric | Target |
|--------|--------|
| Merchants live | 3 |
| POS terminals deployed | 10 |
| Transactions | 100+ |
| Failure rate | < 5% |
| Median settlement time | < 30 min |
| Merchant NPS | > 8/10 |
| Uptime | > 95% |