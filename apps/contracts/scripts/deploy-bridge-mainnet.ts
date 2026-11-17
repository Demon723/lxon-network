import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("Deploying LxonBridgeMultiSig on Ethereum Mainnet...");
  console.log("⚠️ WARNING: This is a production deployment on Ethereum Mainnet");
  console.log("⚠️ This will cost real ETH in gas fees (~0.1-0.15 ETH)");
  console.log("");

  // Use DEPLOYER_PRIVATE_KEY from .env
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No DEPLOYER_PRIVATE_KEY found in environment variables");
  }

  const deployer = new ethers.Wallet(privateKey, ethers.provider);
  console.log("Deploying with account:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");

  if (balance < ethers.parseEther("0.1")) {
    console.log("⚠️ WARNING: Insufficient balance. Minimum 0.1 ETH required for deployment.");
    console.log("Current balance:", ethers.formatEther(balance), "ETH");
    return;
  }

  // Deployment parameters
  const chainId = 1; // Ethereum Mainnet
  const multiSigAttester = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD"; // LXON MultiSigAttester
  const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH on Mainnet
  const timelock = deployer.address; // Deployer as timelock

  console.log("\nDeployment parameters:");
  console.log("Chain ID:", chainId);
  console.log("MultiSigAttester:", multiSigAttester);
  console.log("WETH:", weth);
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
  console.log("WETH:", await bridge.weth());
  console.log("Timelock:", await bridge.timelock());

  console.log("\n⚠️ IMPORTANT: Save this address for peer bridge configuration:");
  console.log("Ethereum Mainnet Bridge Address:", await bridge.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
