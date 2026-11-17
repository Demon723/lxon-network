# LXON Milestone 0: Tokenomics Hardening

## Overview

Milestone 0 focuses on **hardening LXON tokenomics** to remove single-key owner control and establish DAO-governed emission. This is the critical foundation before any public launch or mainnet deployment.

**Status**: ✅ Complete (Contracts deployed and tested)

**Timeline**: Weeks 1-4

## What's Included

### Smart Contracts

#### 1. **LXONHardened.sol** (ERC20 Token)
- **Zero initial supply** — Emission starts via governance only
- **`mintEmission(uint256)`** — Only callable by TimelockController with 48-hour delay
- **`burnFromGovernance(address, uint256)`** — Governance-only burn for deflationary mechanics
- **Public `burn(uint256)`** — Users can burn their own tokens
- **No pause function** — Transfers cannot be halted by anyone
- **Role-based access** — Uses `AccessControl` instead of single `Ownable`
- **Fixed MAX_SUPPLY** — 1 billion tokens, immutable
- **ERC20Votes integration** — Voting power = token balance

**Key Features:**
```solidity
- MAX_SUPPLY: 1,000,000,000 LXON (immutable)
- MINTER_ROLE: Assigned to TimelockController only
- BURNER_ROLE: Assigned to TimelockController only
- Initial supply: 0 (emission via governance)
- No pause mechanism
```

#### 2. **LXONStakingHardened.sol** (Subnet-Based Staking)
- **Subnet allocation** — Yuma-style subnet weighting
- **Emission weight calculation** — Based on staked amount per subnet
- **Taoflow clipping** — Reduce weight if net staking flow is negative
- **Subnet management** — Create, decommission, update weights
- **Lock periods** — Flexible vesting schedules per stake
- **Voting power** — Based on staked amount

**Key Features:**
```solidity
- MIN_STAKE: 1 LXON
- EPOCH_DURATION: 12 hours (Taoflow clipping interval)
- Support for multiple subnets
- Emission weight: 0-10000 (0-100%)
- Lock periods: Configurable per stake
```

#### 3. **LXONGovernanceHardened.sol** (DAO Governance)
- **Governor integration** — OpenZeppelin Governor with TimelockControl
- **48-hour timelock delay** — All governance actions delayed
- **Proposal threshold** — 0.1% of circulating supply (1000 LXON initially)
- **Quorum** — 4% of circulating supply
- **Voting period** — 50,400 blocks (~1 week on Ethereum)
- **Voting delay** — 1 block
- **Proposal types** — EMISSION_PARAMS, BURN_RATE, SUBNET_PARAMS, TREASURY_SPEND

**Governance Flow:**
```
Community proposes → Voting period (1 week) → Quorum check (4%) 
→ Voting approval → Timelock delay (48h) → Execution
```

#### 4. **VestingEscrow.sol** (Team/Treasury Allocations)
- **Linear vesting with cliff** — Configurable vesting schedules
- **Multiple beneficiaries** — Support for team members, contributors
- **Revocable schedules** — Admin can revoke if configured
- **Release mechanism** — Users claim vested tokens when ready
- **Cliff periods** — Delay before vesting starts (e.g., 1 year)

**Example Vesting:**
```
- 1-year cliff (no release)
- 4-year linear vesting (25% per year)
- Revocable by admin if needed
```

## Deployment

### Prerequisites

```bash
# Node.js 20+
node --version

# Hardhat
npm install -g hardhat

# Clone and setup
git clone https://github.com/Demon723/LXON.git
cd LXON/apps/contracts
pnpm install
```

### Environment Setup

Create `.env` file:

```bash
# Network RPC endpoints
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
HOLESKY_RPC_URL=https://eth-holesky.g.alchemy.com/v2/YOUR_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Deployment account (never commit private keys!)
PRIVATE_KEY=0x...

# Etherscan verification
ETHERSCAN_API_KEY=YOUR_KEY
```

### Deploy to Testnet

```bash
# Compile contracts
pnpm run compile

# Deploy to Sepolia testnet
npx hardhat run scripts/deploy-hardened.ts --network sepolia

# Deploy to Holesky testnet
npx hardhat run scripts/deploy-hardened.ts --network holesky

# Output: Contract addresses and deployment info saved to deployments/
```

**Example Output:**
```
🎉 DEPLOYMENT SUCCESSFUL!

📋 CONTRACT ADDRESSES:
LXON Token:                0x...
TimelockController:        0x...
LXONStakingHardened:       0x...
VestingEscrow:             0x...
LXONGovernanceHardened:    0x...
```

### Verify on Etherscan

```bash
# Verify LXON token
npx hardhat verify --network sepolia 0xLXON_ADDRESS 0xGOVERNANCE_ADDRESS 172800

# Verify Staking
npx hardhat verify --network sepolia 0xSTAKING_ADDRESS 0xLXON_ADDRESS 0xGOVERNANCE_ADDRESS 172800

# Verify Vesting
npx hardhat verify --network sepolia 0xVESTING_ADDRESS 0xLXON_ADDRESS

# Verify Governance
npx hardhat verify --network sepolia 0xGOV_ADDRESS 0xLXON_ADDRESS 0xTIMELOCK_ADDRESS
```

## Testing

### Run All Tests

```bash
# Run full test suite
pnpm run test

# Run with gas reporting
REPORT_GAS=true pnpm run test

# Run specific test file
pnpm run test -- test/LXONHardening.test.ts

# Run with coverage
pnpm run test:coverage
```

### Test Coverage

- ✅ **LXONHardened**: Token minting, burning, role-based access
- ✅ **LXONStakingHardened**: Subnet creation, staking, unstaking, weight calculation
- ✅ **LXONGovernanceHardened**: Proposal creation, voting, execution
- ✅ **VestingEscrow**: Schedule creation, vesting calculation, release, revocation
- ✅ **Integration Tests**: Full emission → staking → governance flow

**Target**: 100% branch coverage

## Security Checklist

- [x] Remove `onlyOwner` mint (replaced with `mintEmission` via timelock)
- [x] Remove pause function (no kill switch)
- [x] Replace `Ownable` with `AccessControl` + `TimelockController`
- [x] Zero initial supply (emission starts via governance)
- [x] Fixed MAX_SUPPLY immutable
- [x] Role-based access for all privileged operations
- [x] 48-hour timelock on all governance actions
- [x] Comprehensive test coverage (100% target)
- [ ] External security audit (Milestone 1)
- [ ] Bug bounty program (Milestone 4)

## Security Rating

| Dimension | Current | Target | Status |
|-----------|---------|--------|--------|
| **Contract Permissions** | 2/10 | 8/10 | ✅ Achieved |
| **Audit Coverage** | 0/10 | 7/10 | ⏳ Deferred to Milestone 1 |
| **Host Chain Security** | N/A | 9/10 | ✅ Ethereum L1 (100B+ ETH staked) |
| **Infrastructure** | 5/10 | 8/10 | ⏳ Deferred to Milestone 1 |
| **Monitoring** | 3/10 | 7/10 | ⏳ Deferred to Milestone 1 |
| **Incident Response** | 1/10 | 6/10 | ⏳ Deferred to Milestone 1 |
| **Overall** | **2.5/10** | **7.5/10** | ✅ Contracts Complete |

## Governance Flow Example

### Scenario: Increase Emission Rate

**Day 1: Community Proposes**
```typescript
const proposal = await governor.propose(
  [lxonToken.address],
  [0],
  [lxonToken.interface.encodeFunctionData("mintEmission", [ethers.parseEther("1000000")])],
  "Proposal: Mint 1M LXON for Q4 infrastructure"
);
```

**Day 1-8: Voting Period**
- Voting delay: 1 block
- Voting period: 50,400 blocks (~1 week)
- Quorum required: 4% of LXON supply
- Approval required: Simple majority

**Day 8: Voting Ends, Vote Passes**
```typescript
const state = await governor.state(proposalId);
// State = 4 (Succeeded)
```

**Day 8: Governance Queues Proposal**
```typescript
await governor.queue(
  [lxonToken.address],
  [0],
  [calldata],
  descriptionHash
);
```

**Day 8-10: Timelock Delay (48 hours)**
- Community can veto via social consensus
- Emergency multisig can cancel if issues found

**Day 10: Execute Proposal**
```typescript
await governor.execute(
  [lxonToken.address],
  [0],
  [calldata],
  descriptionHash
);
// Tokens minted to timelock (governance treasury)
```

## Token Economics (Post-Hardening)

### Supply Mechanics
- **Max Supply**: 1,000,000,000 LXOM (immutable)
- **Initial Supply**: 0 (emission via governance only)
- **Emission**: Linear per-block via `mintEmission()`
- **Daily Emission Day 1**: ~13,800 LXOM (adjustable via governance)
- **Schedule**: Declining over 16 years, reaching zero at year 16

### Sinks (Deflationary Pressure)
- **Buyback-and-Burn**: 0.5% of x402 AI-service fees
- **Staking Lock-up**: Staked LXOM removed from circulation
- **Governance-Controlled Burn**: DAO votes to burn surplus

### Allocation (Planned, Not Yet Implemented)

| Pool | Share | Purpose |
|------|-------|---------|
| AI Compute Subnets | 40% | Verifiable-inference provider rewards |
| Capital Providers (Stakers) | 24% | Staking rewards |
| Core Development | 20% | Team + contributors (4-year vesting) |
| Community & Ecosystem | 10% | Grants, bounties, incentives |
| Treasury | 6% | DAO-controlled reserve |

## Next Steps (Milestone 1)

### Frontend
- [ ] Agent wallet component (embedded wallet for x402 payments)
- [ ] Pay-per-analysis UI (contract risk analysis)
- [ ] Subnet dashboard (staking allocation view)
- [ ] Governance panel (proposal voting)

### Backend
- [ ] x402 payment module (HTTP 402 challenge/settlement)
- [ ] Verifiable inference service (OpenGradient/Ritual integration)
- [ ] API endpoints for pay-per-analysis
- [ ] Database models for x402 payments and analyses

### Smart Contracts
- [ ] HeliosPBTv3 verification (physical bound tokens)
- [ ] HeliosCardRegistry (card number generation)
- [ ] HeliosTBAccount (ERC-6551 wallet)

### Testing & Deployment
- [ ] End-to-end integration tests (frontend → backend → contracts)
- [ ] Testnet deployment for x402 endpoints
- [ ] Security audit preparation

## Useful Commands

```bash
# Compile contracts
pnpm run compile

# Run tests
pnpm run test

# Check gas usage
pnpm run test:gas

# Generate coverage report
pnpm run test:coverage

# Deploy to Sepolia
npx hardhat run scripts/deploy-hardened.ts --network sepolia

# Deploy to Holesky
npx hardhat run scripts/deploy-hardened.ts --network holesky

# Verify contract on Etherscan
npx hardhat verify --network sepolia 0xCONTRACT_ADDRESS ...args

# Clean build artifacts
pnpm run clean

# Format code
pnpm run format

# Lint code
pnpm run lint
```

## Important Notes

### ⚠️ Before Mainnet Deployment

1. **External Security Audit** — Get audit from reputable firm (Trail of Bits, OpenZeppelin, etc.)
2. **Multisig Governance** — Use Gnosis Safe for governance address (3/5 threshold minimum)
3. **Timelock Increase** — Consider longer delay for mainnet (e.g., 7 days instead of 48 hours)
4. **Emergency Pause** — Deploy emergency multisig for critical vulnerabilities
5. **Bug Bounty** — Launch on Immunefi or similar platform
6. **Legal Review** — Consult with legal counsel on token classification (utility vs. security)

### ⚠️ Test-Only Features

- `grantRole()` is used in tests to simulate governance flow
- In production, roles are only assigned to `TimelockController`
- Do NOT grant roles to EOAs or other contracts except timelock

## References

- [OpenZeppelin Governor Documentation](https://docs.openzeppelin.com/contracts/latest/governance)
- [ERC20Votes Integration](https://docs.openzeppelin.com/contracts/latest/governance#erc20votes)
- [TimelockController](https://docs.openzeppelin.com/contracts/latest/governance#timelock)
- [Hardhat Deployment Guide](https://hardhat.org/hardhat-runner/docs/advanced/hardhat-runtime-environment)
- [Etherscan Verification](https://hardhat.org/hardhat-runner/plugins/nomiclabs-hardhat-etherscan)

## Support

For issues or questions:
1. Check [LXON GitHub Issues](https://github.com/Demon723/LXON/issues)
2. Review test cases in `test/LXONHardening.test.ts`
3. Check deployment logs in `deployments/`

---

**Milestone 0 Status**: ✅ Complete
**Ready for Milestone 1**: ✅ Yes
**Testnet Ready**: ✅ Sepolia/Holesky
**Mainnet Ready**: ⏳ After security audit
