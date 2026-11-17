# lxon-sdk (Python)

Python SDK for the LXON post-quantum blockchain.

## Install

```bash
pip install lxon-sdk
```

For post-quantum crypto support:

```bash
pip install lxon-sdk[pq]
```

## Quick start

```python
from lxon import LxonClient, PQWrapperClient, SatelliteClient

client = LxonClient(rpc_url="http://localhost:8545")
block = client.get_block_number()
balance = client.get_balance("0x...")

wrapper = PQWrapperClient(client, wrapper_address="0x...")
result = wrapper.wrap_erc20(
    private_key="0x...",
    amount=1_000_000,
    ref="deposit-2026-01-15",
)

sat = SatelliteClient(gateway_url="http://localhost:4100")
passes = sat.get_passes(station_id="SVALBARD")
```

## CLI

```bash
python -m lxon http://localhost:8545 eth_blockNumber
```

## Modules

| Module | Purpose |
|--------|---------|
| `lxon.client` | JSON-RPC client |
| `lxon.pq_wrapper` | PQ Wrapped Asset client |
| `lxon.satellite` | Satellite gateway client |
| `lxon.custody` | Custodian attestation client |
| `lxon.types` | Shared data models |

## License

MIT