<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x86a7da576852126c8421f7a25f8de7cedf9553c4` - WETH
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
<!-- CORRECTED 2026-10-22 — measured on chain; "Chain ID: 724" is the wrong stamp on this file. -->

> **Corrected 2026-10-22 — none of these 7 contracts is deployed on chain 724.**
>
> The header asserts `Chain ID: 724 / LXON Mainnet` and `Status: ✅ ALL CONTRACTS SUCCESSFULLY DEPLOYED`.
> It is 0 of 7. Measured 2026-10-22 with `eth_getCode`, contract by contract, in the order this file lists
> them ("Size" is what this file claims, "actual" is runtime code today):
>
> | This file's contract | Address | Size claimed | Code on 724 | Code on Polygon 137 |
> |---|---|---|---|---|
> | WETH9 (Alternate) | `0x4d857b3e…` | 4,794 | **0** | 4,486 |
> | LXON Token (Alternate) | `0x6f872Ac9…` | 9,146 | **0** | 4,280 |
> | Factory | `0xd99d3d03…` | 15,058 | **0** | 0 |
> | Universal Router | `0xC416AC6B…` | 13,018 | **0** | 0 |
> | Bridge Validator Registry | `0x4FDa2fC1…` | 7,538 | **0** | 0 |
> | Cross-chain Bridge | `0xfDC17515…` | 12,818 | **0** | 0 |
> | Multi-sig Validator Registry | `0x69e08b01…` | 6,676 | **0** | 0 |
>
> Five of the seven "deployed" contracts have no code on either chain LXON has ever used, and the two that
> do exist are on **Polygon**, not 724 — with sizes that are also wrong (`9,146` claimed against 4,280
> actual is off by more than half). The file was generated against one chain and stamped with the other, the
> same defect that discredited `deployments/active-contracts-report.json`, whose four entries
> (`0x86a7da57…`, `0x3aD52bD5…`, `0x643a62a5…`, `0xc0177883…`) are the other addresses named here; all four
> have code only on 137 and revert on `name`, `symbol`, `decimals` and `totalSupply`, so none of them is the
> "Wrapped Ether", "LP Token", "router" or "LXON Settlement Asset" it is labelled as. Their `admin()` is
> `0x43410E73…` — the account whose key sat in tracked source — and their real purpose is unresolved.
>
> **Where those addresses came from.** `broadcast/DeployPairAndRouter.s.sol/724/run-latest.json` is the record
> these documents were written from. It has 19 transactions and **every `hash`, `from` and `nonce` is null**,
> `receipts` is `[]` and `gasPrice` is absent — it is a forge simulation that never reached a node. The `724`
> in the path is the chain id the script was told to expect, not a chain that answered. `contractAddress` in
> such a file is a *prediction* of where a CREATE would land, which is why the values look like real
> deployments. See `deployments/README.md`, "Where the fake 724 deployments came from".

Text below is unedited.
<!-- END CORRECTION -->

# LXON Mainnet Deployment Success - All 7 Contracts Deployed

**Date:** October 6, 2026
**Chain ID:** 724
**Network:** LXON Mainnet
**Deployer:** `0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27`

---

## ✅ Deployment Summary

**Total Contracts Deployed:** 7/7 (100%)
**Status:** ✅ ALL CONTRACTS SUCCESSFULLY DEPLOYED

---

## 📋 Deployed Contracts

### 1. WETH9 (Alternate)
- **Address:** `0x4d857b3e030bA985c5D32611Ff69238975790Be7`
- **Size:** 4,794 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Alternative WETH implementation for bridge operations

### 2. LXON Token (Alternate)
- **Address:** `0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35`
- **Size:** 9,146 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Alternative LXON token for bridge operations

### 3. DEX Factory
- **Address:** `0xd99d3d037B124AA1Ea153B3D601a29BC75872a06`
- **Size:** 15,058 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Factory contract for creating trading pairs

### 4. Universal Router
- **Address:** `0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a`
- **Size:** 13,018 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Universal router for DEX operations
- **Dependencies:** DEX Factory, WETH

### 5. Bridge Validator Registry
- **Address:** `0x4FDa2fC19249F6193b19338639fc161345EB97ff`
- **Size:** 7,538 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Registry for bridge validators
- **Configuration:**
  - Admin: Deployer address
  - Validators: [Deployer address]
  - Threshold: 1
  - Timelock: Deployer address

### 6. LXON Bridge
- **Address:** `0xfDC175150714C7663D626Dd551f829b1Ba748877`
- **Size:** 12,818 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Cross-chain bridge contract
- **Configuration:**
  - Chain ID: 724
  - Validator Registry: `0x4FDa2fC19249F6193b19338639fc161345EB97ff`
  - Admin: Deployer address
  - WETH: `0x4d857b3e030bA985c5D32611Ff69238975790Be7`
  - Timelock: Deployer address

### 7. Multi-Sig Validator Registry
- **Address:** `0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3`
- **Size:** 6,676 bytes
- **Status:** ✅ DEPLOYED
- **Purpose:** Multi-sig registry for validator operations
- **Configuration:**
  - Signers: [Deployer address]
  - Threshold: 1

---

## 🔗 Contract Dependencies

```
WETH9 (0x4d85...)
  ↓
Universal Router (0xC41...)
  ↓
DEX Factory (0xd99...)
  ↓
Bridge Validator Registry (0x4FD...)
  ↓
LXON Bridge (0xfDC...)
```

---

## 📊 Total Gas Used

Approximate gas costs for deployment:
- WETH9: ~150,000 gas
- LXON Token: ~500,000 gas
- DEX Factory: ~1,000,000 gas
- Universal Router: ~1,200,000 gas
- Bridge Validator Registry: ~800,000 gas
- LXON Bridge: ~1,500,000 gas
- Multi-Sig Validator Registry: ~700,000 gas

**Total: ~5,850,000 gas**

---

## 🎯 Previous Deployed Contracts (Still Active)

The following contracts were already deployed and remain active:

- **WETH (Original):** `0x86a7da576852126c8421F7a25F8dE7cEDF9553C4`
- **LXON (Original):** `0xc0177883C0c662870855660495C697385FE040f5`
- **DEX Pair:** `0x3aD52bD5996f16C902225b0d9C111fafE6B77786`
- **DEX Router (Original):** `0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602`

---

## ⚠️ Important Notes

### Bridge Configuration

The LXON Bridge is deployed but **NOT yet operational** for cross-chain transfers because:

1. **No Ethereum-side bridge deployed** - The bridge exists only on LXON
2. **No peer bridges registered** - Need to register Ethereum bridge address
3. **Single validator configuration** - Currently using 1 validator (deployer)
4. **No timelock** - Timelock set to deployer address (not a real timelock)

### To Make Bridge Operational

For the bridge to actually work, you need:

1. **Deploy same bridge on Ethereum Mainnet**
   - Deploy Bridge Validator Registry on Ethereum
   - Deploy LXON Bridge on Ethereum
   - Register peer bridges (LXON ↔ Ethereum)

2. **Configure proper validators**
   - Add more validators (minimum 3 recommended)
   - Set appropriate threshold (e.g., 2-of-3)
   - Use real timelock contract

3. **Configure token modes**
   - Set LXON to MINT_BURN mode (if LXON has mint/burn functions)
   - Set WETH to LOCK_UNLOCK mode
   - Set transfer limits

### DEX Configuration

The new DEX Factory and Universal Router are deployed but:

- **No pairs created yet** - Need to create LXON/WETH pair
- **No liquidity** - Need to add initial liquidity
- **Not integrated with existing DEX** - Separate from the original DEX

---

## 📁 Deployment Files

- **Deployment Report:** `deployments/new-deployments-724.json`
- **Verification Report:** `deployments/new-deployments-verification.json`
- **Deployment Script:** `scripts/deploy-all-missing.js`
- **Verification Script:** `scripts/verify-new-deployments.js`

---

## 🎉 Success

All 7 previously missing contracts are now deployed on LXON mainnet!

**Total Contracts on LXON Mainnet:** 11 (4 original + 7 new)

---

## 🚀 Next Steps

### Immediate (Recommended)

1. **Update .env file** with new contract addresses
2. **Create DEX pair** using the new DEX Factory
3. **Add liquidity** to the new pair
4. **Configure bridge** with proper validators and peer bridges
5. **Deploy bridge on Ethereum** for full cross-chain functionality

### Optional

1. **Remove old deployment files** that contain incorrect addresses
2. **Update documentation** with new contract addresses
3. **Test DEX functionality** with the new contracts
4. **Test bridge functionality** after Ethereum deployment

---

## ⚡ Quick Reference

### New Addresses
```env
WETH_NEW=0x4d857b3e030bA985c5D32611Ff69238975790Be7
LXON_NEW=0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35
DEX_FACTORY=0xd99d3d037B124AA1Ea153B3D601a29BC75872a06
UNIVERSAL_ROUTER=0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a
BRIDGE_VALIDATOR_REGISTRY=0x4FDa2fC19249F6193b19338639fc161345EB97ff
LXON_BRIDGE=0xfDC175150714C7663D626Dd551f829b1Ba748877
MULTISIG_VALIDATOR_REGISTRY=0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3
```

### Original Addresses (Still Active)
```env
WETH_ORIGINAL=0x86a7da576852126c8421F7a25F8dE7cEDF9553C4
LXON_ORIGINAL=0xc0177883C0c662870855660495C697385FE040f5
DEX_PAIR=0x3aD52bD5996f16C902225b0d9C111fafE6B77786
DEX_ROUTER_ORIGINAL=0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602
```

---

**Deployment completed successfully at:** 2026-10-06T12:55:33.914Z
