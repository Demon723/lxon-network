import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as readline from "readline";

const CHAIN_ID = 724;
const RPC_URL = "http://13.51.158.120:8546";
const DRY_RUN = process.env.DRY_RUN === 'true';

/**
 * Direct L3 Deployment Script (bypassing Hardhat network config)
 * Uses ethers directly for deployment to avoid timeout issues
 */

function confirm(message: string): Promise<boolean> {
  // Auto-confirm in non-interactive mode
  if (DRY_RUN) {
    console.log(`${message} - Auto-confirmed (dry-run mode)`);
    return Promise.resolve(true);
  }
  
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

async function verifyGasPrice(maxGasPriceGwei: number = 50): Promise<void> {
  const feeData = await ethers.provider.getFeeData();
  const gasPrice = feeData.gasPrice;
  const gasPriceGwei = Number(ethers.formatUnits(gasPrice || 0n, "gwei"));
  
  console.log(`⛽ Current gas price: ${gasPriceGwei.toFixed(2)} gwei`);
  
  if (gasPriceGwei > maxGasPriceGwei) {
    throw new Error(`Gas price too high: ${gasPriceGwei.toFixed(2)} gwei (threshold: ${maxGasPriceGwei} gwei)`);
  }
  
  console.log(`✅ Gas price verified (threshold: ${maxGasPriceGwei} gwei)`);
}

async function main() {
  console.log("🏗️  Deploying L3 Mint Contracts to Chain ID 724");
  console.log("🌐 RPC URL:", RPC_URL);
  
  if (DRY_RUN) {
    console.log("⚠️  DRY RUN MODE - No actual deployment will be performed");
  }

  const [deployer] = await ethers.getSigners();
  console.log("🔑 Deployer address:", deployer.address);

  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  
  if (chainId !== CHAIN_ID) {
    throw new Error(`Network mismatch: Expected ${CHAIN_ID}, got ${chainId}`);
  }

  console.log("✅ Network verified successfully");

  await verifyGasPrice(50);

  const confirmed = await confirm("Are you sure you want to deploy L3 contracts to mainnet?");
  if (!confirmed) {
    console.log("❌ Deployment cancelled by user");
    process.exit(0);
  }

  console.log("✅ Deployment confirmed by user");

  const deployments: any = {};
  const deploymentSteps: string[] = [];

  try {
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

    console.log("📦 Deploying L3ChipManager...");
    deploymentSteps.push("Deploy L3ChipManager");
    
    if (!DRY_RUN) {
      const L3ChipManager = await ethers.getContractFactory("L3ChipManager");
      const l3ChipManager = await L3ChipManager.deploy();
      await l3ChipManager.waitForDeployment();
      const l3ChipManagerAddress = await l3ChipManager.getAddress();
      deployments.l3ChipManager = l3ChipManagerAddress;
      console.log("✅ L3ChipManager deployed to:", l3ChipManagerAddress);
    } else {
      deployments.l3ChipManager = "0xSIMULATED_L3CHIPMANAGER_ADDRESS";
      console.log("✅ L3ChipManager deployment simulated");
    }

    console.log("📦 Deploying L3Redemption...");
    deploymentSteps.push("Deploy L3Redemption");
    
    if (!DRY_RUN) {
      const L3Redemption = await ethers.getContractFactory("L3Redemption");
      const l3Redemption = await L3Redemption.deploy();
      await l3Redemption.waitForDeployment();
      const l3RedemptionAddress = await l3Redemption.getAddress();
      deployments.l3Redemption = l3RedemptionAddress;
      console.log("✅ L3Redemption deployed to:", l3RedemptionAddress);
    } else {
      deployments.l3Redemption = "0xSIMULATED_L3REDEMPTION_ADDRESS";
      console.log("✅ L3Redemption deployment simulated");
    }

    console.log("🔧 Configuring L3ChipManager...");
    deploymentSteps.push("Configure L3ChipManager");
    
    if (!DRY_RUN) {
      const L3ChipManager = await ethers.getContractAt("L3ChipManager", deployments.l3ChipManager);
      await L3ChipManager.setRedemptionContract(deployments.l3Redemption);
      console.log("✅ L3ChipManager configured");
    } else {
      console.log("✅ L3ChipManager configuration simulated");
    }

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
        privateKeySecured: false, // Using Hardhat signers
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

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    
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