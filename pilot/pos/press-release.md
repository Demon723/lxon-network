# Press Release — Helios Satellite POS Pilot

**FOR IMMEDIATE RELEASE**

## LXON launches world's first satellite-powered point-of-sale pilot in rural Kenya

**NAIROBI, Kenya** — [Date] — LXON Labs today announced the launch of a
4-week pilot of Helios, the world's first satellite-powered point-of-sale
terminal, across 3 rural merchants outside Nairobi.

The pilot deploys 10 Helios terminals to coffee shops, market stalls, and
kiosks in regions where the mobile network is unreliable or absent. Unlike
traditional card terminals that depend on cellular connectivity, Helios
uses Iridium satellite SBD to settle payments on-chain — in under 30 minutes,
with no bank account required.

"This is the moment LXON stops being a whitepaper and starts being real,"
said [CEO name], founder of LXON Labs. "We built a Layer-1 that can do
something no other chain can: process a payment at the edge of coverage,
with post-quantum security, and settle it on-chain. This pilot proves it."

### How it works

1. Customer taps card or phone on the Helios terminal
2. Terminal signs the transaction with ML-DSA-65 (FIPS-204) via a secure element
3. Signature is sent over Iridium SBD to the LXON gateway
4. Gateway submits the anchor to the `SatelliteSignatureV2` contract
5. Settlement reaches the merchant's M-Pesa or bank account in under 30 minutes

### Pilot metrics

| Metric | Target |
|--------|--------|
| Terminals deployed | 10 |
| Merchants live | 3 |
| Transactions | 100+ |
| Failure rate | < 5% |
| Median settlement | < 30 min |

### Why it matters

- **Financial inclusion**: 1.7B adults worldwide lack bank access. Helios
  requires only a card or phone.
- **Resilience**: In areas with frequent network outages, Helios keeps
  transacting when traditional terminals go dark.
- **Post-quantum security**: ML-DSA-65 signatures protect against future
  quantum attacks — a first for point-of-sale.

### About LXON

LXON is a Layer-1 blockchain purpose-built for satellite-anchored
infrastructure. It combines post-quantum cryptography, Iridium/Astrocast
satellite connectivity, and on-chain verification to enable payments,
data markets, and identity at the edge of coverage.

**Press contact**: press@lxon.example | +254-XXX-XXXX

---