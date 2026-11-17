import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Adding Liquidity to SushiSwap (Polygon)\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // SushiSwap Router (Polygon)
  const SUSHISWAP_ROUTER = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
  const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

  // LXON address on Polygon
  const LXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  console.log("\n=== Configuration ===");
  console.log("SushiSwap Router:", SUSHISWAP_ROUTER);
  console.log("WMATIC:", WMATIC);
  console.log("LXON:", LXON_ADDRESS);

  // Target price: $1.50 per LXON
  const TARGET_PRICE_USD = 1.5;
  const MATIC_PRICE_USD = 0.5; // Current MATIC price
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

    // Calculate liquidity amounts - use 2 LXON for initial liquidity (fits current balance)
    const LXON_AMOUNT = ethers.parseUnits("2", 6);
    const WMATIC_AMOUNT = ethers.parseEther(String(2 * TARGET_WMATIC_PER_LXON));

    console.log("\n=== Liquidity to Add ===");
    console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("WMATIC amount:", ethers.formatEther(WMATIC_AMOUNT));
    console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");
    console.log("Total Value: ~$", (2 * TARGET_PRICE_USD * 2).toFixed(2));

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
      return;
    }

    // Approve SushiSwap Router to spend LXON
    console.log("\n=== Approving SushiSwap Router ===");
    const approveTx = await lxon.approve(SUSHISWAP_ROUTER, LXON_AMOUNT);
    console.log("Approval transaction:", approveTx.hash);
    await approveTx.wait();
    console.log("✅ LXON approved");

    // Get SushiSwap Router interface
    const routerAbi = [
      "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)"
    ];
    const router = await ethers.getContractAt(routerAbi, SUSHISWAP_ROUTER);

    // Add liquidity to SushiSwap
    console.log("\n=== Adding Liquidity to SushiSwap ===");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    // Use legacy transaction format for Polygon
    const addLiquidityTx = await router.addLiquidity(
      LXON_ADDRESS,
      WMATIC,
      LXON_AMOUNT,
      WMATIC_AMOUNT,
      LXON_AMOUNT * 95n / 100n,  // 5% slippage tolerance
      WMATIC_AMOUNT * 95n / 100n, // 5% slippage tolerance
      deployerAddress,
      deadline,
      { 
        value: WMATIC_AMOUNT,
        gasPrice: ethers.parseUnits("30", "gwei"), // Fixed gas price for Polygon
        gasLimit: 500000 // Sufficient gas limit
      }
    );

    console.log("Liquidity transaction:", addLiquidityTx.hash);
    const receipt = await addLiquidityTx.wait();

    console.log("\n✅ Liquidity added successfully!");
    console.log("Transaction hash:", receipt?.hash);
    console.log("Gas used:", receipt?.gasUsed.toString());

    console.log("\n=== Success ===");
    console.log("Liquidity added to SushiSwap");
    console.log("Price should be approximately $1.50 per LXON");
    console.log("TVL: ~$", (2 * TARGET_PRICE_USD * 2).toFixed(2));
    console.log("\n🎉 You can now trade wLXON on SushiSwap!");
    console.log("Visit: https://app.sushi.com/");
    console.log("Search for wLXON/WMATIC pair");

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
    if (error.message.includes("network does not support EIP-1559")) {
      console.log("\n💡 SushiSwap may require legacy transactions");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
