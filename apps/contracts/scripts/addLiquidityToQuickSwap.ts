import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Adding Liquidity to QuickSwap (Polygon)\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // QuickSwap Router (Polygon)
  const QUICKSWAP_ROUTER = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
  const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

  // LXON address on Polygon (replace after bridge deployment)
  const LXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  console.log("\n=== Configuration ===");
  console.log("QuickSwap Router:", QUICKSWAP_ROUTER);
  console.log("WMATIC:", WMATIC);
  console.log("LXON:", LXON_ADDRESS);

  // Target price: $1.50 per LXON
  const TARGET_PRICE_USD = 1.5;
  const MATIC_PRICE_USD = 0.5; // Updated MATIC price (more current)
  const TARGET_WMATIC_PER_LXON = TARGET_PRICE_USD / MATIC_PRICE_USD;

  console.log("\n=== Price Target ===");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("MATIC price: $", MATIC_PRICE_USD);
  console.log("Target WMATIC per LXON:", TARGET_WMATIC_PER_LXON);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 137n) {
    console.log("\n⚠️  WARNING: This script is for Polygon Mainnet (Chain ID 137)");
    console.log("Current network is not Polygon Mainnet");
    console.log("Please configure hardhat.config.ts for Polygon network");
    return;
  }

  // Connect to LXONWrapper contract
  try {
    const lxon = await ethers.getContractAt("LXONWrapper", LXON_ADDRESS);
    const lxonBalance = await lxon.balanceOf(deployerAddress);
    const maticBalance = await ethers.provider.getBalance(deployerAddress);

    console.log("\n=== Balances ===");
    console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
    console.log("MATIC balance:", ethers.formatEther(maticBalance));

    // Calculate liquidity amounts
    // Use 5 LXON for initial liquidity (smaller amount for testing)
    const LXON_AMOUNT = ethers.parseUnits("5", 6);
    const WMATIC_AMOUNT = ethers.parseEther(String(5 * TARGET_WMATIC_PER_LXON));

    console.log("\n=== Liquidity to Add ===");
    console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("WMATIC amount:", ethers.formatEther(WMATIC_AMOUNT));
    console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");
    console.log("Total Value: ~$", (5 * TARGET_PRICE_USD * 2).toFixed(2));

    if (lxonBalance < LXON_AMOUNT) {
      console.log("\n❌ Insufficient LXON balance");
      console.log("Need:", ethers.formatUnits(LXON_AMOUNT, 6));
      console.log("Have:", ethers.formatUnits(lxonBalance, 6));
      return;
    }

    if (maticBalance < WMATIC_AMOUNT) {
      console.log("\n❌ Insufficient MATIC balance");
      console.log("Need:", ethers.formatEther(WMATIC_AMOUNT), "MATIC");
      console.log("Have:", ethers.formatEther(maticBalance), "MATIC");
      console.log("\n💡 Get MATIC from: https://faucet.polygon.technology/");
      return;
    }

    // Approve QuickSwap Router to spend LXON
    console.log("\n=== Approving QuickSwap Router ===");
    const approveTx = await lxon.approve(QUICKSWAP_ROUTER, LXON_AMOUNT);
    console.log("Approval transaction:", approveTx.hash);
    await approveTx.wait();
    console.log("✅ LXON approved");

    // Get QuickSwap Router interface
    const routerAbi = [
      "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)",
      "function factory() external view returns (address)"
    ];
    const router = await ethers.getContractAt(routerAbi, QUICKSWAP_ROUTER);

    // Add liquidity to QuickSwap
    console.log("\n=== Adding Liquidity to QuickSwap ===");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const addLiquidityTx = await router.addLiquidity(
      LXON_ADDRESS,
      WMATIC,
      LXON_AMOUNT,
      WMATIC_AMOUNT,
      LXON_AMOUNT * 95n / 100n,  // 5% slippage tolerance
      WMATIC_AMOUNT * 95n / 100n, // 5% slippage tolerance
      deployerAddress,
      deadline,
      { value: WMATIC_AMOUNT }
    );

    console.log("Liquidity transaction:", addLiquidityTx.hash);
    const receipt = await addLiquidityTx.wait();

    console.log("\n✅ Liquidity added successfully!");
    console.log("Transaction hash:", receipt?.hash);
    console.log("Gas used:", receipt?.gasUsed.toString());

    console.log("\n=== Success ===");
    console.log("Liquidity added to QuickSwap");
    console.log("Price should be approximately $1.50 per LXON");
    console.log("TVL: ~$", (5 * TARGET_PRICE_USD * 2).toFixed(2));
    console.log("\n🎉 You can now trade wLXON on QuickSwap!");
    console.log("Visit: https://quickswap.exchange/");
    console.log("Search for wLXON/WMATIC pair");

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
    if (error.message.includes("network does not support EIP-1559")) {
      console.log("\n💡 QuickSwap may require legacy transactions");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
