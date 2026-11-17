import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("💸 Transfer MATIC to Deployer Address\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [sender] = await ethers.getSigners();
  const senderAddress = await sender.getAddress();
  
  // Deployer address that needs MATIC
  const deployerAddress = "0xc5Bb37D6A66A1c5E00D4987e460Ab40d702ec82A";

  console.log("From:", senderAddress);
  console.log("To:", deployerAddress);

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

  // Check sender balance
  const senderBalance = await ethers.provider.getBalance(senderAddress);
  console.log("\n=== Sender Balance ===");
  console.log("MATIC balance:", ethers.formatEther(senderBalance));

  if (senderBalance < ethers.parseEther("0.01")) {
    console.log("\n❌ Insufficient MATIC balance");
    console.log("Need: 0.01+ MATIC");
    console.log("Have:", ethers.formatEther(senderBalance), "MATIC");
    console.log("\n💡 Get MATIC from faucet:");
    console.log("   https://faucet.polygon.technology/");
    console.log("   Address:", senderAddress);
    return;
  }

  // Amount to transfer (0.6 MATIC for setup)
  const transferAmount = ethers.parseEther("0.6");
  
  console.log("\n=== Transfer Details ===");
  console.log("Amount:", ethers.formatEther(transferAmount), "MATIC");
  console.log("To:", deployerAddress);

  if (senderBalance < transferAmount) {
    console.log("\n⚠️  WARNING: Transferring most of your balance");
    console.log("Available:", ethers.formatEther(senderBalance), "MATIC");
    console.log("Transferring:", ethers.formatEther(transferAmount), "MATIC");
    console.log("Remaining:", ethers.formatEther(senderBalance - transferAmount), "MATIC");
  }

  // Execute transfer
  console.log("\n=== Executing Transfer ===");
  const tx = await sender.sendTransaction({
    to: deployerAddress,
    value: transferAmount
  });

  console.log("Transaction hash:", tx.hash);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();

  console.log("\n✅ Transfer successful!");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Check new balances
  const newSenderBalance = await ethers.provider.getBalance(senderAddress);
  const deployerBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== New Balances ===");
  console.log("Sender:", ethers.formatEther(newSenderBalance), "MATIC");
  console.log("Deployer:", ethers.formatEther(deployerBalance), "MATIC");

  console.log("\n🎉 MATIC transferred successfully!");
  console.log("You can now proceed with Polygon liquidity setup");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
