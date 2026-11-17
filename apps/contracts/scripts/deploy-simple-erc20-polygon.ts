import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LXON Test Token on Polygon");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Deployer address:", signer.address);

  // Deploy simple ERC20 for testing
  console.log("\nDeploying simple test token on Polygon...");
  const TestToken = await ethers.getContractFactory("TestToken");
  
  const testToken = await TestToken.deploy("LXON Test", "LXON", 6);
  
  console.log("Transaction hash:", testToken.deploymentTransaction().hash);
  console.log("Waiting for confirmation...");
  
  await testToken.waitForDeployment();
  const tokenAddress = await testToken.getAddress();
  
  console.log("✅ Test token deployed:", tokenAddress);
  console.log("\nToken details:");
  console.log("  Name:", await testToken.name());
  console.log("  Symbol:", await testToken.symbol());
  console.log("  Decimals:", await testToken.decimals());

  // Mint 1M tokens to deployer
  console.log("\nMinting 1M tokens to deployer...");
  const mintTx = await testToken.mint(signer.address, ethers.parseUnits("1000000", 6));
  await mintTx.wait();
  console.log("✅ Minting successful");

  // Check balance
  const balance = await testToken.balanceOf(signer.address);
  console.log("Deployer balance:", ethers.formatUnits(balance, 6), "LXON");

  console.log("\n=== Deployment Complete ===");
  console.log("Test Token Address:", tokenAddress);
  console.log("\nAdd this to .env:");
  console.log(`POLYGON_LXON_ADDRESS=${tokenAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
