import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying REAL LXON Token on Polygon Mainnet");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Deployer address:", signer.address);

  // Deploy the actual LXON contract (same as on LXON chain)
  console.log("\nDeploying LXON Settlement Asset contract...");
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

  // Set up roles for minting
  console.log("\nSetting up minting permissions...");
  const MINT_ROLE = await lxon.MINT_ROLE();
  
  // Grant MINT_ROLE to deployer
  const grantTx = await lxon.grantRole(MINT_ROLE, signer.address);
  await grantTx.wait();
  console.log("✅ MINT_ROLE granted to deployer");

  // Set reserve ceiling for minting (set to 1B USD = 100B cents)
  const ceilingTx = await lxon.updateCeiling(100000000000, ethers.ZeroHash);
  await ceilingTx.wait();
  console.log("✅ Reserve ceiling set to 1B USD");

  // Mint initial supply for liquidity
  console.log("\nMinting initial supply for liquidity...");
  const mintAmount = ethers.parseUnits("10000000", 0); // 10M LXON
  const mintTx = await lxon.mint(signer.address, mintAmount, ethers.ZeroHash);
  await mintTx.wait();
  console.log("✅ Minted 10M LXON to deployer");

  // Verify balance
  const balance = await lxon.balanceOf(signer.address);
  console.log("Deployer balance:", ethers.formatUnits(balance, 6), "LXON");

  console.log("\n=== Deployment Complete ===");
  console.log("LXON Token Address:", lxonAddress);
  console.log("\nAdd this to .env:");
  console.log(`POLYGON_LXON_ADDRESS=${lxonAddress}`);
  console.log("\n⚠️  PRODUCTION DEPLOYMENT - Token is now live on Polygon mainnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
