import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LXON Wrapper (wLXON) to Polygon\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 137n) {
    console.log("\n⚠️  WARNING: This script is for Polygon Mainnet (Chain ID 137)");
    console.log("Current network is not Polygon Mainnet");
    console.log("Please ensure you're using --network polygon");
    return;
  }

  // Check MATIC balance
  const maticBalance = await ethers.provider.getBalance(deployerAddress);
  console.log("\n=== MATIC Balance ===");
  console.log("Balance:", ethers.formatEther(maticBalance), "MATIC");

  if (maticBalance < ethers.parseEther("0.01")) {
    console.log("\n❌ Insufficient MATIC balance");
    console.log("Need: 0.01+ MATIC");
    console.log("Have:", ethers.formatEther(maticBalance), "MATIC");
    return;
  }

  console.log("✅ Sufficient MATIC balance\n");

  // Original LXON address on LXON network (for reference)
  const originalLXON = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  console.log("=== Deployment Configuration ===");
  console.log("Original LXON (LXON network):", originalLXON);
  console.log("Wrapped token will be: wLXON on Polygon");
  console.log("Decimals: 6 (same as original LXON)\n");

  // Deploy LXON Wrapper
  console.log("=== Deploying LXON Wrapper ===");
  const LXONWrapper = await ethers.getContractFactory("LXONWrapper");
  
  const wrapper = await LXONWrapper.deploy(originalLXON);
  console.log("Deployment transaction:", wrapper.deploymentTransaction()?.hash);
  await wrapper.waitForDeployment();
  
  const wrapperAddress = await wrapper.getAddress();
  console.log("✅ LXON Wrapper deployed at:", wrapperAddress);
  console.log("Token Name: LXON Wrapped");
  console.log("Token Symbol: wLXON");
  console.log("Decimals: 6\n");

  // Mint initial supply to deployer
  console.log("=== Minting Initial Supply ===");
  const initialSupply = ethers.parseUnits("1000000", 6); // 1,000,000 wLXON
  
  const mintTx = await wrapper.mint(deployerAddress, initialSupply);
  console.log("Mint transaction:", mintTx.hash);
  await mintTx.wait();
  console.log("✅ Minted 1,000,000 wLXON to deployer");
  console.log("Balance:", ethers.formatUnits(await wrapper.balanceOf(deployerAddress), 6), "wLXON\n");

  console.log("=== Deployment Summary ===");
  console.log("Contract Address:", wrapperAddress);
  console.log("Token Name: LXON Wrapped");
  console.log("Token Symbol: wLXON");
  console.log("Decimals: 6");
  console.log("Total Supply: 1,000,000 wLXON");
  console.log("Your Balance: 1,000,000 wLXON");
  console.log("\n💡 Save this address for QuickSwap liquidity:");
  console.log("   POLYGON_LXON_ADDRESS=", wrapperAddress);
  console.log("\n🎉 You can now add liquidity to QuickSwap!");
  console.log("Run: npx hardhat run scripts/addLiquidityToQuickSwap.ts --network polygon");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
