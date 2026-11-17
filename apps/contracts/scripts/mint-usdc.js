const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Mint USDC for Liquidity ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const usdcAddress = process.env.USDC_ADDRESS;
  console.log("USDC Address:", usdcAddress);

  const USDC = await ethers.getContractFactory("USDC");
  const usdc = USDC.attach(usdcAddress);

  // Mint 111.6M USDC (same as WETH amount for $2/LXON)
  const amountToMint = ethers.parseUnits("111600000", 6); // USDC has 6 decimals

  console.log("Minting 111,600,000 USDC to:", deployer.address);

  const tx = await usdc.mint(deployer.address, amountToMint);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ Successfully minted 111.6M USDC!");

  const balance = await usdc.balanceOf(deployer.address);
  console.log("New USDC balance:", ethers.formatUnits(balance, 6), "USDC");

  console.log("\n=== Next Steps ===");
  console.log("1. Create LXON/USDC DEX pair");
  console.log("2. Add liquidity to achieve $2/LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
