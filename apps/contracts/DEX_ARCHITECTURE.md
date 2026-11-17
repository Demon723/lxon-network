# LXON DEX Architecture

## Overview
Complete DEX implementation with factory pattern for dynamic pair creation.

## Components

### 1. DEXFactory.sol
**Purpose**: Factory contract to create trading pairs dynamically

**Features**:
- Create unlimited trading pairs (tokenA/tokenB)
- Pair address deterministic (CREATE2)
- Fee collection mechanism
- Owner-controlled fee management

**Key Functions**:
- `createPair(tokenA, tokenB)` - Creates new trading pair
- `setFeeTo(address)` - Sets fee recipient
- `setFeeToSetter(address)` - Sets fee manager

### 2. Pair.sol (Updated)
**Purpose**: Individual trading pair contract

**Changes**:
- Modified constructor to support factory deployment
- Added `initialize()` function for post-deployment setup
- Maintains Uniswap V2 compatibility

**Features**:
- ERC20 LP tokens
- Constant product AMM (x*y=k)
- Flash swap support
- Reserve synchronization

### 3. UniversalRouter.sol
**Purpose**: Universal router for all trading operations

**Features**:
- Create pairs via factory
- Add/remove liquidity
- Swap tokens (single and multi-hop)
- Slippage protection
- Deadline enforcement

**Key Functions**:
- `createPair(tokenA, tokenB)` - Create new trading pair
- `addLiquidity(...)` - Provide liquidity to pair
- `removeLiquidity(...)` - Remove liquidity
- `swapExactTokensForTokens(...)` - Swap with exact input
- `swapTokensForExactTokens(...)` - Swap with exact output

## Deployment Steps

### 1. Deploy Factory and Router
```bash
npx hardhat run scripts/deploy-dex-factory.ts --network mainnet
```

### 2. Create Trading Pairs
```bash
npx hardhat run scripts/use-dex-factory.ts --network mainnet
```

### 3. Add Liquidity
```typescript
await router.addLiquidity(
  lxonAddress,
  usdcAddress,
  amountLXON,
  amountUSDC,
  amountLXONMin,
  amountUSDCMin,
  recipient,
  deadline
);
```

### 4. Swap Tokens
```typescript
await router.swapExactTokensForTokens(
  amountIn,
  amountOutMin,
  [lxonAddress, usdcAddress],
  recipient,
  deadline
);
```

## Supported Token Pairs

The factory enables ANY ERC20 token pair:
- LXON/USDC
- LXON/USDT
- LXON/WETH
- USDC/USDT
- Any custom token pair

## Price Calculation

Uses constant product formula:
```
amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
```

Fee: 0.3% (30 basis points)

## Security Features

- Reentrancy guards
- Slippage protection
- Deadline enforcement
- Owner controls for critical functions
- Factory pattern prevents duplicate pairs

## Gas Optimization

- CREATE2 for deterministic addresses
- Minimal storage operations
- Efficient math operations
- Batch operations support

## Next Steps

1. ✅ Factory contract
2. ✅ Universal router
3. ⏳ Price oracle integration (Chainlink)
4. ⏳ Liquidity mining/staking
5. ⏳ Limit orders
6. ⏳ Flash loans
7. ⏳ Governance system

## Files Created

- `contracts/DEXFactory.sol` - Factory contract
- `contracts/UniversalRouter.sol` - Universal router
- `contracts/Pair.sol` - Updated pair contract
- `scripts/deploy-dex-factory.ts` - Deployment script
- `scripts/use-dex-factory.ts` - Usage example
