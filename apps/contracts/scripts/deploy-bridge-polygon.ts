import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("Deploying LxonBridgeMultiSig on Polygon...");
  console.log("⚠️ NOTE: Polygon is a Layer 2 with lower gas costs than Ethereum Mainnet");
  console.log("");

  // Use custom deployer address for Polygon
  const deployerAddress = "0xc5Bb37D6A66A1c5E00D4987e460Ab40d702ec82A";
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const deployer = new ethers.Wallet(privateKey, ethers.provider);
  console.log("Deploying with account:", deployerAddress);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "MATIC");

  if (balance < ethers.parseEther("0.01")) {
    console.log("⚠️ WARNING: Insufficient balance. Minimum 0.01 MATIC required for deployment.");
    console.log("Current balance:", ethers.formatEther(balance), "MATIC");
    console.log("Please get MATIC from: https://faucet.polygon.technology/");
    return;
  }

  // Deployment parameters
  const chainId = 137; // Polygon Mainnet
  const multiSigAttester = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD"; // LXON MultiSigAttester
  const weth = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"; // WMATIC on Polygon
  const timelock = deployer.address; // Deployer as timelock

  console.log("\nDeployment parameters:");
  console.log("Chain ID:", chainId);
  console.log("MultiSigAttester:", multiSigAttester);
  console.log("WETH (WMATIC):", weth);
  console.log("Timelock:", timelock);

  // Deploy contract
  console.log("\nDeploying LxonBridgeMultiSig...");
  const LxonBridgeMultiSig = await ethers.getContractFactory("LxonBridgeMultiSig");
  const bridge = await LxonBridgeMultiSig.deploy(
    chainId,
    multiSigAttester,
    weth,
    timelock
  );

  console.log("Transaction hash:", bridge.deploymentTransaction().hash);
  console.log("Waiting for deployment...");

  await bridge.waitForDeployment();

  console.log("\n✅ LxonBridgeMultiSig deployed successfully!");
  console.log("Address:", await bridge.getAddress());
  console.log("Chain ID:", await bridge.chainId());
  console.log("MultiSigAttester:", await bridge.multiSigAttester());
  console.log("WETH (WMATIC):", await bridge.weth());
  console.log("Timelock:", await bridge.timelock());

  console.log("\n⚠️ IMPORTANT: Save this address for peer bridge configuration:");
  console.log("Polygon Bridge Address:", await bridge.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
