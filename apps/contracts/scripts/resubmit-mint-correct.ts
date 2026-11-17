import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Resubmitting wLXON Mint Transaction\n");
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
    // Check current nonce
    const latestNonce = await ethers.provider.getTransactionCount(deployerAddress, "latest");
    const pendingNonce = await ethers.provider.getTransactionCount(deployerAddress, "pending");
    
    console.log("\n=== Current Nonce State ===");
    console.log("Latest nonce:", latestNonce);
    console.log("Pending nonce:", pendingNonce);
    console.log("Next nonce to use:", latestNonce);

    // Connect to wLXON contract with custom ABI
    const wlxonAbi = [
      "function mint(address to, uint256 amount) external",
      "function balanceOf(address account) external view returns (uint256)",
      "function decimals() external view returns (uint8)",
      "function totalSupply() external view returns (uint256)"
    ];
    const wlxon = await ethers.getContractAt(wlxonAbi, WLXON_ADDRESS);
    
    // Check current balance
    const balance = await wlxon.balanceOf(deployerAddress);
    const decimals = await wlxon.decimals();

    console.log("\n=== Current wLXON Balance ===");
    console.log("Decimals:", decimals.toString());
    console.log("Current Balance:", ethers.formatUnits(balance, decimals));
    console.log("Raw Balance:", balance.toString());

    // Mint 1,000,000 wLXON (18 decimals)
    const MINT_AMOUNT = ethers.parseUnits("1000000", 18);
    console.log("\n=== Minting ===");
    console.log("Amount to mint:", ethers.formatUnits(MINT_AMOUNT, 18), "wLXON");
    console.log("Raw amount:", MINT_AMOUNT.toString());

    // Get current gas price
    const feeData = await ethers.provider.getFeeData();
    const gasPrice = feeData.gasPrice;
    console.log("\n=== Gas ===");
    console.log("Current gas price:", ethers.formatUnits(gasPrice || 0, "gwei"), "gwei");
    
    // Set gas price to 400 gwei to ensure confirmation
    const gasPriceToUse = ethers.parseUnits("400", "gwei");
    console.log("Using gas price:", ethers.formatUnits(gasPriceToUse, "gwei"), "gwei");

    // Mint tokens
    console.log("\n=== Submitting Mint Transaction ===");
    const mintTx = await wlxon.mint(deployerAddress, MINT_AMOUNT, {
      gasPrice: gasPriceToUse
    });

    console.log("Transaction hash:", mintTx.hash);
    console.log("Nonce:", mintTx.nonce);
    console.log("Waiting for confirmation...");

    const receipt = await mintTx.wait();

    console.log("\n✅ Mint Transaction Confirmed!");
    console.log("Block Number:", receipt?.blockNumber);
    console.log("Gas Used:", receipt?.gasUsed.toString());
    console.log("Transaction Hash:", receipt?.hash);

    // Check new balance
    const newBalance = await wlxon.balanceOf(deployerAddress);
    console.log("\n=== New Balance ===");
    console.log("Balance:", ethers.formatUnits(newBalance, decimals), "wLXON");
    console.log("Raw Balance:", newBalance.toString());

    console.log("\n🎉 Success! You now have 1,000,000 wLXON on Polygon!");
    console.log("You can now add liquidity to SushiSwap.");

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
