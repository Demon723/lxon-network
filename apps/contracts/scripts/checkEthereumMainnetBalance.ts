import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Checking Ethereum Mainnet balance");
  console.log("Account:", deployer.address);
  
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);
  
  if (network.chainId !== 1n) {
    console.log("\n⚠️  WARNING: Not on Ethereum Mainnet (Chain ID 1)");
    console.log("Current chain ID:", network.chainId);
    console.log("This script requires Ethereum Mainnet (Chain ID 1)");
  }
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("\n=== Balance ===");
  console.log("ETH balance:", ethers.formatEther(balance));
  console.log("ETH value (at $3,000): $", Number(ethers.formatEther(balance)) * 3000);
  
  const REQUIRED_ETH = ethers.parseEther("0.1"); // 0.1 ETH for gas
  console.log("\n=== Requirements ===");
  console.log("Required ETH for deployment:", ethers.formatEther(REQUIRED_ETH));
  console.log("Required ETH value: $", Number(ethers.formatEther(REQUIRED_ETH)) * 3000);
  
  if (balance < REQUIRED_ETH) {
    console.log("\n❌ INSUFFICIENT ETH BALANCE");
    console.log("You need at least 0.1 ETH for deployment gas fees");
    console.log("Please add ETH to your account to proceed");
  } else {
    console.log("\n✅ SUFFICIENT ETH BALANCE");
    console.log("You have enough ETH for deployment");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
