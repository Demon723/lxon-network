import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔍 Checking Current wLXON Status\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  const WLXON_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  try {
    // Connect to wLXON contract
    const wlxon = await ethers.getContractAt("ERC20", WLXON_ADDRESS);
    
    // Check balance
    const balance = await wlxon.balanceOf(deployerAddress);
    const decimals = await wlxon.decimals();
    const totalSupply = await wlxon.totalSupply();

    console.log("\n=== wLXON Token Info ===");
    console.log("Contract Address:", WLXON_ADDRESS);
    console.log("Decimals:", decimals.toString());
    console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals));
    console.log("Your Balance:", ethers.formatUnits(balance, decimals));
    console.log("Raw Balance:", balance.toString());

    // Check transaction status
    const txHash = "0x3c1d5acde625abc8c3813c4760ff869b116ca6e5408da5a588ac501338d2afe2";
    console.log("\n=== Transaction Status ===");
    console.log("Transaction Hash:", txHash);
    
    try {
      const tx = await ethers.provider.getTransaction(txHash);
      if (tx) {
        console.log("Transaction found in mempool");
        console.log("From:", tx.from);
        console.log("To:", tx.to);
        console.log("Nonce:", tx.nonce);
        console.log("Gas Price:", ethers.formatUnits(tx.gasPrice || 0, "gwei"), "gwei");
      } else {
        console.log("Transaction not found in mempool (might be confirmed or dropped)");
      }
    } catch (error: any) {
      console.log("Error checking transaction:", error.message);
    }

    try {
      const receipt = await ethers.provider.getTransactionReceipt(txHash);
      if (receipt) {
        console.log("\n✅ Transaction Confirmed!");
        console.log("Block Number:", receipt.blockNumber);
        console.log("Status:", receipt.status === 1 ? "Success" : "Failed");
        console.log("Gas Used:", receipt.gasUsed.toString());
      } else {
        console.log("\n⏳ Transaction receipt not found (still pending or dropped)");
      }
    } catch (error: any) {
      console.log("Error checking receipt:", error.message);
    }

    // Check account nonce
    const nonce = await ethers.provider.getTransactionCount(deployerAddress, "latest");
    const pendingNonce = await ethers.provider.getTransactionCount(deployerAddress, "pending");
    console.log("\n=== Account Nonce ===");
    console.log("Latest nonce:", nonce);
    console.log("Pending nonce:", pendingNonce);

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
