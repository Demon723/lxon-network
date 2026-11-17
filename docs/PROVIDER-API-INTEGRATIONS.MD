# Provider API Integrations

LXON integrates with two provider APIs for fee payment and settlement:

## Spacecoin RPC

- **Purpose**: Pay anchor fees in LXON's Layer-2 settlement token.
- **Contract**: `apps/contracts/contracts/provider/SpacecoinRPC.sol`
- **Methods**: `transfer`, `balanceOf`
- **RPC URL**: Configured at deploy time by governance.

## SEALCOIN REST

- **Purpose**: Pay data-availability fees for satellite telemetry.
- **Contract**: `apps/contracts/contracts/provider/SealcoinREST.sol`
- **Mechanism**: Signed relay requests submitted by a permissioned relayer.
- **Signature**: ECDSA over `keccak256(token, amount, deadline, nonce)`.

## Gateway flow

1. Gateway batches anchors per satellite.
2. For each batch, submits one tx to `SatelliteSignatureV2.anchor`.
3. Gateway pays anchor fees via Spacecoin RPC.
4. Data-availability fees are relayed via SEALCOIN REST.
5. Relayer submits the batched REST requests off-chain.

## Governance

Both provider contracts are governed. The RPC URL and relayer address
can only be changed by the governance address.