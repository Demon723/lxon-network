import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LXON Token on Sepolia Testnet");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Deployer address:", signer.address);

  // Deploy LXON token
  console.log("\nDeploying LXON token...");
  const LXON = await ethers.getContractFactory("LXON");
  const lxon = await LXON.deploy(signer.address);
  
  console.log("Transaction hash:", lxon.deploymentTransaction().hash);
  console.log("Waiting for confirmation...");
  
  await lxon.waitForDeployment();
  const lxonAddress = await lxon.getAddress();
  
  console.log("✅ LXON token deployed:", lxonAddress);
  console.log("\nToken details:");
  console.log("  Name:", await lxon.name());
  console.log("  Symbol:", await lxon.symbol());
  console.log("  Decimals:", await lxon.decimals());
  console.log("  Total Supply:", ethers.formatUnits(await lxon.totalSupply(), 6), "LXON");

  // Mint initial supply for testing
  console.log("\nMinting initial supply for testing...");
  const mintAmount = ethers.parseUnits("1000000", 6); // 1M LXON
  const MINT_ROLE = await lxon.MINT_ROLE();
  
  // Grant MINT_ROLE to deployer
  const grantTx = await lxon.grantRole(MINT_ROLE, signer.address);
  await grantTx.wait();
  console.log("✅ MINT_ROLE granted to deployer");

  // Mint to deployer
  const mintTx = await lxon.mint(signer.address, ethers.parseUnits("1000000", 0), ethers.ZeroHash);
  await mintTx.wait();
  console.log("✅ Minted 1M LXON to deployer");

  // Verify balance
  const balance = await lxon.balanceOf(signer.address);
  console.log("Deployer balance:", ethers.formatUnits(balance, 6), "LXON");

  console.log("\n=== Deployment Complete ===");
  console.log("LXON Token Address:", lxonAddress);
  console.log("\nAdd this to .env:");
  console.log(`SEPOLIA_LXON_ADDRESS=${lxonAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
