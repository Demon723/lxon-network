const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Check USDC Balance ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const usdcAddress = process.env.USDC_ADDRESS;
  console.log("USDC Address:", usdcAddress);

  const USDC = await ethers.getContractFactory("USDC");
  const usdc = USDC.attach(usdcAddress);

  const balance = await usdc.balanceOf(deployer.address);
  const decimals = await usdc.decimals();
  const symbol = await usdc.symbol();

  console.log("Symbol:", symbol);
  console.log("Decimals:", decimals);
  console.log("Balance:", ethers.formatUnits(balance, decimals), symbol);
  console.log("Raw Balance:", balance.toString());

  console.log("\n=== Mint More USDC ===");
  const amountToMint = ethers.parseUnits("111600000", 18); // 111.6M USDC with 18 decimals

  console.log("Minting 111,600,000 USDC...");
  const tx = await usdc.mint(deployer.address, amountToMint);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ Minted!");

  const newBalance = await usdc.balanceOf(deployer.address);
  console.log("New Balance:", ethers.formatUnits(newBalance, decimals), symbol);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
