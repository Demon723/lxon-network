const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy USDC Stablecoin ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const USDC = await ethers.getContractFactory("USDC");
  const usdc = await USDC.deploy();
  await usdc.waitForDeployment();

  const usdcAddress = await usdc.getAddress();
  console.log("✅ USDC deployed to:", usdcAddress);

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`USDC_ADDRESS=${usdcAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Mint USDC for liquidity");
  console.log("2. Create LXON/USDC DEX pair");
  console.log("3. Add liquidity to achieve $2/LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
