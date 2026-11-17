import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("Deploying LxonBridgeMultiSig on Holesky Testnet...");

  // Use DEPLOYER_PRIVATE_KEY from .env
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const deployer = new ethers.Wallet(privateKey, ethers.provider);
  console.log("Deploying with account:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");

  // Deployment parameters
  const chainId = 17000; // Holesky Testnet
  const multiSigAttester = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD"; // LXON MultiSigAttester
  const weth = "0x9c3c9283D5E3d0f4Ab4EE0a00790089629476f76"; // WETH on Holesky
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
  console.log("Holesky Bridge Address:", await bridge.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
