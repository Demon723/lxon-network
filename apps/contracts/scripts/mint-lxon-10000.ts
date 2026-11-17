import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Minting 10,000 LXON on LXON Network\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 724n) {
    console.log("\n❌ Wrong network! Please use --network lxonMainnet");
    return;
  }

  const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

  try {
    // Connect to LXON contract
    const lxon = await ethers.getContractAt("LXON", LXON_ADDRESS);
    
    // Check current balance
    const balance = await lxon.balanceOf(deployerAddress);
    const decimals = await lxon.decimals();

    console.log("\n=== Current LXON Balance ===");
    console.log("Decimals:", decimals.toString());
    console.log("Current Balance:", ethers.formatUnits(balance, decimals), "LXON");

    // Mint 10,000 LXON (6 decimals)
    // LXON mint requires: address to, uint256 usdCents, bytes32 depositRef
    // amount = usdCents * 1e4 (1 USD = 10,000 LXON in raw units)
    // With 6 decimals: to get 10,000 displayed LXON, we need:
    // 10,000 * 10^6 = 10,000,000,000 raw units
    // usdCents = 10,000,000,000 / 10,000 = 1,000,000
    // 1,000,000 cents = $10,000 USD
    const USD_CENTS = 1000000; // $10,000 USD
    const DEPOSIT_REF = ethers.ZeroHash; // Use zero hash for deposit reference
    
    console.log("\n=== Minting ===");
    console.log("USD Cents:", USD_CENTS, "($10,000 USD)");
    console.log("Deposit Ref:", DEPOSIT_REF);
    console.log("Expected LXON amount:", USD_CENTS * 1e4 / 1e6, "LXON"); // Convert back to display

    // Get current gas price
    const feeData = await ethers.provider.getFeeData();
    const gasPrice = feeData.gasPrice;
    console.log("\n=== Gas ===");
    console.log("Current gas price:", ethers.formatUnits(gasPrice || 0, "gwei"), "gwei");

    // Mint tokens
    console.log("\n=== Submitting Mint Transaction ===");
    const mintTx = await lxon.mint(deployerAddress, USD_CENTS, DEPOSIT_REF);

    console.log("Transaction hash:", mintTx.hash);
    console.log("Nonce:", mintTx.nonce);
    console.log("Waiting for confirmation...");

    const receipt = await mintTx.wait();

    console.log("\n✅ Mint Transaction Confirmed!");
    console.log("Block Number:", receipt?.blockNumber);
    console.log("Gas Used:", receipt?.gasUsed.toString());
    console.log("Transaction Hash:", receipt?.hash);

    // Check new balance
    const newBalance = await lxon.balanceOf(deployerAddress);
    console.log("\n=== New Balance ===");
    console.log("Balance:", ethers.formatUnits(newBalance, decimals), "LXON");
    console.log("Raw Balance:", newBalance.toString());

    console.log("\n🎉 Success! You now have LXON on LXON network!");
    console.log("Note: LXON uses USD cents for minting. 1 USD = 10,000 LXON");
    console.log("You can now add liquidity to the LXON/WETH pair.");

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
