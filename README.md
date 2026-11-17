# LXON

LXON Network — a sovereign EVM blockchain (chain ID 724) running Besu in QBFT
consensus with Ethereum Cancun EVM rules, plus the ERC-20 settlement asset LXON
and the WETH/USDC market and bridge contracts.

## Documentation

- **Whitepaper:** [`docs/WHITEPAPER.md`](docs/WHITEPAPER.md) — also published at
  <https://github.com/Demon723/lxon-whitepaper>
- Tokenomics: [`docs/TOKENOMICS.MD`](docs/TOKENOMICS.MD)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## Layout

- `apps/contracts` — Solidity contracts (LXON token, bridge, AMM, oracles)
- `apps/lxon-blockchain` — chain node / RPC server
- `apps/frontend`, `apps/backend`, `apps/wallet` — web and service components
- `lxon-evm-node` — Besu-based EVM node configuration
- `crates`, `firmware`, `sdk`, `packages` — Rust crates, Helios firmware, SDKs

## Notes

- This is a source export built from a single squashed snapshot — it has no
  upstream git history by design.
- Contract ABIs and typechain types live under `apps/contracts`.
