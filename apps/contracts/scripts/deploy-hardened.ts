import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Deployment script for LXON Hardened contracts to testnet
 * Deploys in order:
 * 1. LXONHardened token
 * 2. LXONStakingHardened
 * 3. LXONGovernanceHardened
 * 4. VestingEscrow
 */

interface DeploymentConfig {
  governance: string;
  timelockDelay: number;
  network: string;
  timestamp: string;
}

interface DeploymentResult {
  config: DeploymentConfig;
  contracts: {
    lxonToken: string;
    timelock: string;
    staking: string;
    governance: string;
    vesting: string;
  };
}

async function main() {
  console.log("🚀 Starting LXON Hardened Contract Deployment...\n");

  const [deployer] = await ethers.getSigners();
  console.log("📋 Deployer Address:", deployer.address);

  const network = await ethers.provider.getNetwork();
  console.log("🌐 Network:", network.name, `(Chain ID: ${network.chainId})\n`);

  // Configuration
  const TIMELOCK_DELAY = 172800; // 48 hours
  const GOVERNANCE_ADDRESS = deployer.address; // In production, use actual governance contract
  
  const config: DeploymentConfig = {
    governance: GOVERNANCE_ADDRESS,
    timelockDelay: TIMELOCK_DELAY,
    network: network.name,
    timestamp: new Date().toISOString(),
  };

  console.log("⚙️  Deployment Configuration:");
  console.log(`   - Timelock Delay: ${TIMELOCK_DELAY} seconds (48 hours)`);
  console.log(`   - Governance: ${GOVERNANCE_ADDRESS}`);
  console.log(`   - Network: ${network.name}\n`);

  const result: DeploymentResult = {
    config,
    contracts: {
      lxonToken: "",
      timelock: "",
      staking: "",
      governance: "",
      vesting: "",
    },
  };

  try {
    // ============ 1. Deploy LXONHardened Token ============
    console.log("📦 Deploying LXONHardened Token...");
    const LXONFactory = await ethers.getContractFactory("LXONHardened");
    const lxon = await LXONFactory.deploy(GOVERNANCE_ADDRESS, TIMELOCK_DELAY);
    await lxon.waitForDeployment();
    const lxonAddress = await lxon.getAddress();

    result.contracts.lxonToken = lxonAddress;
    console.log(`✅ LXONHardened deployed at: ${lxonAddress}`);

    // Get timelock address
    const timelockAddress = await lxon.timelock();
    result.contracts.timelock = timelockAddress;
    console.log(`✅ TimelockController deployed at: ${timelockAddress}\n`);

    // ============ 2. Deploy LXONStakingHardened ============
    console.log("📦 Deploying LXONStakingHardened...");
    const StakingFactory = await ethers.getContractFactory(
      "LXONStakingHardened"
    );
    const staking = await StakingFactory.deploy(
      lxonAddress,
      GOVERNANCE_ADDRESS,
      TIMELOCK_DELAY
    );
    await staking.waitForDeployment();
    const stakingAddress = await staking.getAddress();

    result.contracts.staking = stakingAddress;
    console.log(`✅ LXONStakingHardened deployed at: ${stakingAddress}\n`);

    // ============ 3. Deploy VestingEscrow ============
    console.log("📦 Deploying VestingEscrow...");
    const VestingFactory = await ethers.getContractFactory("VestingEscrow");
    const vesting = await VestingFactory.deploy(lxonAddress);
    await vesting.waitForDeployment();
    const vestingAddress = await vesting.getAddress();

    result.contracts.vesting = vestingAddress;
    console.log(`✅ VestingEscrow deployed at: ${vestingAddress}\n`);

    // ============ 4. Deploy LXONGovernanceHardened ============
    console.log("📦 Deploying LXONGovernanceHardened...");

    // Get timelock contract instance
    const timelock = await ethers.getContractAt(
      "TimelockController",
      timelockAddress
    );

    const GovernanceFactory = await ethers.getContractFactory(
      "LXONGovernanceHardened"
    );
    const governance = await GovernanceFactory.deploy(lxonAddress, timelockAddress);
    await governance.waitForDeployment();
    const governanceAddress = await governance.getAddress();

    result.contracts.governance = governanceAddress;
    console.log(`✅ LXONGovernanceHardened deployed at: ${governanceAddress}\n`);

    // ============ Verification & Setup ============
    console.log("🔍 Verifying deployment...\n");

    // Check token properties
    const maxSupply = await lxon.MAX_SUPPLY();
    const totalSupply = await lxon.totalSupply();
    console.log(`   Token Max Supply: ${ethers.formatEther(maxSupply)} LXON`);
    console.log(`   Token Total Supply: ${ethers.formatEther(totalSupply)} LXON`);

    // Check roles
    const MINTER_ROLE = ethers.id("MINTER_ROLE");
    const BURNER_ROLE = ethers.id("BURNER_ROLE");
    const hasMinterRole = await lxon.hasRole(MINTER_ROLE, timelockAddress);
    const hasBurnerRole = await lxon.hasRole(BURNER_ROLE, timelockAddress);

    console.log(
      `   ✅ TimelockController has MINTER_ROLE: ${hasMinterRole}`
    );
    console.log(
      `   ✅ TimelockController has BURNER_ROLE: ${hasBurnerRole}`
    );

    // Check governance setup
    const govVotingDelay = await governance.votingDelay();
    const govVotingPeriod = await governance.votingPeriod();
    const govQuorum = await governance.quorumNumerator();

    console.log(`\n   Governance Settings:`);
    console.log(`   - Voting Delay: ${govVotingDelay} blocks`);
    console.log(`   - Voting Period: ${govVotingPeriod} blocks`);
    console.log(`   - Quorum: ${govQuorum}%\n`);

    // ============ Save Deployment Info ============
    console.log("💾 Saving deployment information...");

    const deploymentDir = path.join(
      __dirname,
      "../deployments"
    );
    if (!fs.existsSync(deploymentDir)) {
      fs.mkdirSync(deploymentDir, { recursive: true });
    }

    const filename = path.join(
      deploymentDir,
      `${network.name}-${Date.now()}.json`
    );
    fs.writeFileSync(filename, JSON.stringify(result, null, 2));
    console.log(`✅ Deployment info saved to: ${filename}\n`);

    // ============ Output Summary ============
    console.log("═".repeat(70));
    console.log("🎉 DEPLOYMENT SUCCESSFUL!\n");
    console.log("📋 CONTRACT ADDRESSES:");
    console.log("─".repeat(70));
    console.log(`LXON Token:                ${result.contracts.lxonToken}`);
    console.log(`TimelockController:        ${result.contracts.timelock}`);
    console.log(`LXONStakingHardened:       ${result.contracts.staking}`);
    console.log(`VestingEscrow:             ${result.contracts.vesting}`);
    console.log(`LXONGovernanceHardened:    ${result.contracts.governance}`);
    console.log("─".repeat(70));

    console.log("\n📝 NEXT STEPS:");
    console.log("1. Verify contracts on Etherscan:");
    console.log(
      `   npx hardhat verify --network ${network.name} ${result.contracts.lxonToken} ${GOVERNANCE_ADDRESS} ${TIMELOCK_DELAY}`
    );
    console.log(
      `   npx hardhat verify --network ${network.name} ${result.contracts.staking} ${result.contracts.lxonToken} ${GOVERNANCE_ADDRESS} ${TIMELOCK_DELAY}`
    );
    console.log(
      `   npx hardhat verify --network ${network.name} ${result.contracts.vesting} ${result.contracts.lxonToken}`
    );
    console.log(
      `   npx hardhat verify --network ${network.name} ${result.contracts.governance} ${result.contracts.lxonToken} ${result.contracts.timelock}`
    );
    console.log("\n2. Test deployment with:");
    console.log(
      `   npx hardhat test --network ${network.name} test/LXONHardening.test.ts`
    );
    console.log("\n3. For mainnet deployment:");
    console.log("   - Use a multisig as GOVERNANCE address");
    console.log("   - Increase TIMELOCK_DELAY to production value");
    console.log("   - Get external security audit");
    console.log("═".repeat(70) + "\n");

    return result;
  } catch (error) {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
