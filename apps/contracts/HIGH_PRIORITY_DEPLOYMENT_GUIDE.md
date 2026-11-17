# High Priority Enhancements - Deployment Guide

## Overview
This guide covers deployment of the three **High Priority** enhancements:
1. Multi-sig validator signatures (Bridge security)
2. Timelock for admin functions (Governance security)
3. Permit/ERC2612 to token (Gas optimization)

## Prerequisites

- Foundry installed
- Private key set in environment variable `PRIVATE_KEY`
- RPC endpoint configured in foundry.toml
- Test funds for deployment

## Step 1: Deploy Enhanced Contracts

### Deploy to Anvil (Test)
```bash
cd /Users/adikamble/LXON/LXON/apps/contracts

# Set private key
export PRIVATE_KEY=0xREPLACE_WITH_YOUR_OWN_DEPLOYER_PRIVATE_KEY

# Deploy enhanced token and bridge
forge script script/DeployHighPriorityEnhancements.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

### Deploy to Testnet
```bash
# Use testnet RPC and real private key
forge script script/DeployHighPriorityEnhancements.s.sol \
  --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY \
  --broadcast \
  --verify
```

## Step 2: Verify Enhancements

### Run Verification Tests
```bash
forge test --match-test testTimelockDelay \
  --match-test testPermitGaslessApproval \
  --match-test testMultiSigValidatorSignatures \
  -vv
```

### Expected Results
- ✅ Timelock operations require 48-hour delay
- ✅ Permit enables gasless approvals
- ✅ Multi-sig requires threshold signatures (default: 2)

## Step 3: Configure Bridge

### Add Validators
```solidity
// Each validator must stake minimum amount
bridge.addValidator(validator1Address, 10000 * 1e6);
bridge.addValidator(validator2Address, 10000 * 1e6);
bridge.addValidator(validator3Address, 10000 * 1e6);
```

### Set Threshold
```solidity
// Via timelock (recommended)
bytes memory setData = abi.encodeWithSignature(
    "setMinConfirmations(uint256)",
    uint256(3)  // Require 3 signatures
);
bytes32 timelockId = token.scheduleTimelock(address(bridge), setData);

// Execute after 48 hours
skip(48 hours);
token.executeTimelock(timelockId);
```

### Register Peer Bridges
```solidity
bridge.setPeerBridge(137, polygonBridgeAddress);  // Polygon
bridge.setPeerChainId(56, true);                  // BSC
```

## Step 4: Use Permit for Gasless Operations

### Frontend Integration
```javascript
import { ethers } from 'ethers';

// Sign permit off-chain
const permit = {
  owner: userAddress,
  spender: bridgeAddress,
  value: amount,
  nonce: await token.nonces(userAddress),
  deadline: Math.floor(Date.now() / 1000) + 3600
};

const signature = await signer._signTypedData(
  token.domainSeparator,
  permitTypes,
  permit
);

// Use permit in bridge transaction
await bridge.initiateTransferWithPermit(
  tokenAddress,
  amount,
  targetChainId,
  recipient,
  permit.deadline,
  signature.v,
  signature.r,
  signature.s
);
```

### Gas Savings
- Regular approve: ~46,000 gas
- Permit on-chain: ~27,000 gas
- **Savings: ~19,000 gas (~41%)**

## Step 5: Monitor Timelock Operations

### Check Timelock Status
```solidity
// Check if timelock is ready to execute
bool ready = token.isTimelockReady(timelockId);

// Get timelock details
LxonTokenEnhanced.TimelockOperation memory op = token.getTimelock(timelockId);
```

### Execute Timelock
```solidity
// After 48 hours have passed
if (block.timestamp >= op.executeTime) {
    token.executeTimelock(timelockId);
}
```

## Step 6: Test Multi-sig Bridge Operation

### Initiate Transfer
```solidity
// User approves tokens
token.approve(address(bridge), amount);

// Initiate transfer
bytes32 transferId = bridge.initiateTransfer(
    tokenAddress,
    amount,
    targetChainId,
    recipient
);
```

### Validators Sign
```solidity
// Validator 1 signs
bridge.signTransfer(transferId);

// Validator 2 signs (threshold met, executes automatically)
bridge.signTransfer(transferId);
```

### Check Signature Count
```solidity
uint256 count = bridge.getSignatureCount(transferId);
// Returns number of validators who have signed
```

## Security Checklist

### Pre-Deployment
- [ ] Review timelock delay (48 hours)
- [ ] Set appropriate validator threshold (minimum 2)
- [ ] Verify validator staking requirements
- [ ] Test permit signature validation
- [ ] Configure circuit breakers

### Post-Deployment
- [ ] Verify roles are correctly assigned
- [ ] Test timelock schedule/execute/cancel
- [ ] Test permit with real signatures
- [ ] Test multi-sig with minimum threshold
- [ ] Monitor gas costs
- [ ] Set up monitoring for circuit breaker events

### Emergency Procedures
- [ ] Document timelock cancellation process
- [ ] Prepare emergency withdraw procedures
- [ ] Test circuit breaker activation
- [ ] Verify flash loan protection works

## Monitoring

### Key Events to Monitor
```solidity
// Timelock events
event TimelockScheduled(bytes32 indexed operationId, address indexed target, uint256 executeTime);
event TimelockExecuted(bytes32 indexed operationId, address indexed executor);
event TimelockCancelled(bytes32 indexed operationId, address indexed canceller);

// Multi-sig events
event ValidatorSigned(bytes32 indexed transferId, address indexed validator);
event TransferCompleted(bytes32 indexed transferId, address indexed recipient);

// Circuit breaker events
event CircuitBreakerTriggered(string functionType, bool paused, address indexed triggerer);
```

### Dashboard Metrics
- Active timelock operations
- Pending transfers awaiting signatures
- Validator signature counts
- Circuit breaker status
- Gas usage trends

## Rollback Procedure

If issues arise after deployment:

1. **Pause operations:**
   ```solidity
   token.triggerCircuitBreaker(true, true, true, true);
   bridge.triggerCircuitBreaker(true, true, true);
   ```

2. **Cancel pending timelocks:**
   ```solidity
   token.cancelTimelock(timelockId);
   ```

3. **Remove validators:**
   ```solidity
   bridge.removeValidator(maliciousValidator);
   ```

4. **Emergency withdraw:**
   ```solidity
   bridge.emergencyWithdraw(tokenAddress, amount);
   ```

## Next Steps

After high-priority deployment:

1. **Short-term (Medium Priority):**
   - Implement batch operations
   - Optimize staking storage
   - Add comprehensive event logging

2. **Long-term (Strategic):**
   - Cross-chain message passing
   - Yield-bearing staking
   - LayerZero/Wormhole integration

## Support

For issues or questions:
- Check deployment logs in `broadcast/` directory
- Review verification test output
- Consult `LXON_ENHANCEMENTS_SUMMARY.md` for full details
