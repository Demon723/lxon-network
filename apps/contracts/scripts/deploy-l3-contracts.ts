import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as readline from "readline";

const CHAIN_ID = 724;
const RPC_URL = "http://13.51.158.120:8546";
const DRY_RUN = process.env.DRY_RUN === 'true';

/**
 * L3 Mint Smart Contract Deployment Script
 * 
 * Security-Enhanced Deployment Script with:
 * - Secure private key management
 * - Deployment confirmation prompts
 * - Gas price verification
 * - Dry-run mode
 * - Rollback capability
 * 
 * Deploys L3 layer smart contracts to Chain ID 724:
 * - L3MintToken: Token management for physical assets
 * - L3ChipManager: Physical chip registration and management
 * - L3Redemption: Token redemption for physical assets
 */

// Security: Confirmation prompt function
function confirm(message: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  return new Promise((resolve) => {
    rl.question(`${message} (yes/no): `, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === 'yes');
    });
  });
}

// Security: Gas price verification
async function verifyGasPrice(maxGasPriceGwei: number = 50): Promise<void> {
  const gasPrice = await ethers.provider.getGasPrice();
  const gasPriceGwei = Number(ethers.formatUnits(gasPrice, "gwei"));
  
  console.log(`⛽ Current gas price: ${gasPriceGwei.toFixed(2)} gwei`);
  
  if (gasPriceGwei > maxGasPriceGwei) {
    throw new Error(`Gas price too high: ${gasPriceGwei.toFixed(2)} gwei (threshold: ${maxGasPriceGwei} gwei)`);
  }
  
  console.log(`✅ Gas price verified (threshold: ${maxGasPriceGwei} gwei)`);
}

// Security: Secure private key loading
function getDeployer(): ethers.Signer {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error("DEPLOYER_PRIVATE_KEY environment variable not set. Please set it before deployment.");
  }
  
  if (privateKey.length !== 66 || !privateKey.startsWith('0x')) {
    throw new Error("Invalid private key format. Must be 66 characters starting with '0x'");
  }
  
  console.log("✅ Private key loaded from environment variable");
  return new ethers.Wallet(privateKey, ethers.provider);
}

async function main() {
  console.log("🏗️  Deploying L3 Mint Contracts to Chain ID 724");
  console.log("🌐 RPC URL:", RPC_URL);
  
  if (DRY_RUN) {
    console.log("⚠️  DRY RUN MODE - No actual deployment will be performed");
  }

  // Security: Secure private key loading
  const deployer = getDeployer();
  console.log("🔑 Deployer address:", deployer.address);

  // Verify network
  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  
  if (chainId !== CHAIN_ID) {
    throw new Error(`Network mismatch: Expected ${CHAIN_ID}, got ${chainId}`);
  }

  console.log("✅ Network verified successfully");

  // Security: Gas price verification
  await verifyGasPrice(50);

  // Security: Deployment confirmation
  const confirmed = await confirm("Are you sure you want to deploy L3 Mint contracts to mainnet?");
  if (!confirmed) {
    console.log("❌ Deployment cancelled by user");
    process.exit(0);
  }

  console.log("✅ Deployment confirmed by user");

  const deployments: any = {};
  const deploymentSteps: string[] = [];

  try {
    // Deploy L3MintToken
    console.log("📦 Deploying L3MintToken...");
    deploymentSteps.push("Deploy L3MintToken");
    
    if (!DRY_RUN) {
      const L3MintToken = await ethers.getContractFactory("L3MintToken");
      const l3MintToken = await L3MintToken.deploy();
      await l3MintToken.waitForDeployment();
      const l3MintTokenAddress = await l3MintToken.getAddress();
      deployments.l3MintToken = l3MintTokenAddress;
      console.log("✅ L3MintToken deployed to:", l3MintTokenAddress);
    } else {
      deployments.l3MintToken = "0xSIMULATED_L3MINTTOKEN_ADDRESS";
      console.log("✅ L3MintToken deployment simulated");
    }

    // Deploy L3ChipManager
    console.log("📦 Deploying L3ChipManager...");
    deploymentSteps.push("Deploy L3ChipManager");
    
    if (!DRY_RUN) {
      const L3ChipManager = await ethers.getContractFactory("L3ChipManager");
      const l3ChipManager = await L3ChipManager.deploy(deployments.l3MintToken);
      await l3ChipManager.waitForDeployment();
      const l3ChipManagerAddress = await l3ChipManager.getAddress();
      deployments.l3ChipManager = l3ChipManagerAddress;
      console.log("✅ L3ChipManager deployed to:", l3ChipManagerAddress);
    } else {
      deployments.l3ChipManager = "0xSIMULATED_L3CHIPMANAGER_ADDRESS";
      console.log("✅ L3ChipManager deployment simulated");
    }

    // Deploy L3Redemption
    console.log("📦 Deploying L3Redemption...");
    deploymentSteps.push("Deploy L3Redemption");
    
    if (!DRY_RUN) {
      const L3Redemption = await ethers.getContractFactory("L3Redemption");
      const l3Redemption = await L3Redemption.deploy(
        deployments.l3MintToken,
        deployments.l3ChipManager
      );
      await l3Redemption.waitForDeployment();
      const l3RedemptionAddress = await l3Redemption.getAddress();
      deployments.l3Redemption = l3RedemptionAddress;
      console.log("✅ L3Redemption deployed to:", l3RedemptionAddress);
    } else {
      deployments.l3Redemption = "0xSIMULATED_L3REDEMPTION_ADDRESS";
      console.log("✅ L3Redemption deployment simulated");
    }

    // Configure L3ChipManager with redemption contract
    console.log("🔧 Configuring L3ChipManager...");
    deploymentSteps.push("Configure L3ChipManager");
    
    if (!DRY_RUN) {
      const L3ChipManager = await ethers.getContractAt("L3ChipManager", deployments.l3ChipManager);
      await L3ChipManager.setRedemptionContract(deployments.l3Redemption);
      console.log("✅ L3ChipManager configured");
    } else {
      console.log("✅ L3ChipManager configuration simulated");
    }

    // Save deployment record
    const deploymentRecord = {
      network: "lxon-mainnet",
      chainId: CHAIN_ID,
      timestamp: new Date().toISOString(),
      deployer: deployer.address,
      dryRun: DRY_RUN,
      deploymentSteps: deploymentSteps,
      contracts: deployments,
      security: {
        gasPriceVerified: true,
        privateKeySecured: true,
        userConfirmed: true
      }
    };

    const deploymentDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentDir)) {
      fs.mkdirSync(deploymentDir, { recursive: true });
    }

    const deploymentPath = path.join(deploymentDir, "l3-contracts-deployment.json");
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentRecord, null, 2));

    console.log("\n🎉 L3 Mint Contracts Deployment Complete!");
    console.log("📊 Summary:");
    console.log("   ✅ L3MintToken:", deployments.l3MintToken);
    console.log("   ✅ L3ChipManager:", deployments.l3ChipManager);
    console.log("   ✅ L3Redemption:", deployments.l3Redemption);
    console.log("📄 Deployment record saved to:", deploymentPath);

    // Verification steps
    console.log("\n🔍 Verification steps:");
    console.log("   1. Check contract balances");
    console.log("   2. Verify contract ownership");
    console.log("   3. Test basic contract functions");
    console.log("   4. Verify integration with L1 chain");
    console.log("   5. Verify contract on block explorer");

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    
    // Security: Rollback procedure
    console.log("\n🔄 Rollback procedure:");
    console.log("   1. Review deployment record for partial deployments");
    console.log("   2. Verify contract states on chain");
    console.log("   3. If contracts were deployed, verify their configuration");
    console.log("   4. Document rollback steps taken");
    
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });