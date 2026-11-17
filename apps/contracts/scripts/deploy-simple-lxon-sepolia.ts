import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying Simple LXON Test Token on Sepolia");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Deployer address:", signer.address);

  // Deploy simple ERC20 for testing
  console.log("\nDeploying simple LXON test token...");
  const TestToken = await ethers.getContractFactory("contracts/LXONNativeTokenEnhanced.sol:LXONNativeTokenEnhanced");
  
  // Deploy with placeholder addresses for chip/card registries (not needed for testing)
  const testToken = await TestToken.deploy(signer.address, signer.address);
  
  console.log("Transaction hash:", testToken.deploymentTransaction().hash);
  console.log("Waiting for confirmation...");
  
  await testToken.waitForDeployment();
  const tokenAddress = await testToken.getAddress();
  
  console.log("✅ Test token deployed:", tokenAddress);
  console.log("\nToken details:");
  console.log("  Name:", await testToken.name());
  console.log("  Symbol:", await testToken.symbol());
  console.log("  Decimals:", await testToken.decimals());

  // Use dailyEmission to mint tokens
  console.log("\nTriggering daily emission to mint tokens...");
  const emissionTx = await testToken.dailyEmission();
  await emissionTx.wait();
  console.log("✅ Daily emission successful");

  // Check balance
  const balance = await testToken.balanceOf(signer.address);
  console.log("Deployer balance:", ethers.formatUnits(balance, 18), "LXON");

  console.log("\n=== Deployment Complete ===");
  console.log("Test Token Address:", tokenAddress);
  console.log("\nAdd this to .env:");
  console.log(`SEPOLIA_LXON_ADDRESS=${tokenAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
