import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Adding Liquidity to QuickSwap V3 (Polygon)\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // QuickSwap V3 Router (Polygon)
  const QUICKSWAP_V3_ROUTER = await ethers.getAddress("0x8359f3Ad8847817547F9fB2c5FfCf65a16C687a9");
  const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

  // LXON address on Polygon
  const LXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  console.log("\n=== Configuration ===");
  console.log("QuickSwap V3 Router:", QUICKSWAP_V3_ROUTER);
  console.log("WMATIC:", WMATIC);
  console.log("LXON:", LXON_ADDRESS);

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

    // Calculate liquidity amounts
    const LXON_AMOUNT = ethers.parseUnits("5", 6);
    const WMATIC_AMOUNT = ethers.parseEther("15");

    console.log("\n=== Liquidity to Add ===");
    console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("WMATIC amount:", ethers.formatEther(WMATIC_AMOUNT));
    console.log("Total Value: ~$15.00");

    if (lxonBalance < LXON_AMOUNT) {
      console.log("\n❌ Insufficient LXON balance");
      return;
    }

    if (maticBalance < WMATIC_AMOUNT) {
      console.log("\n❌ Insufficient MATIC balance");
      return;
    }

    // Approve router
    console.log("\n=== Approving QuickSwap V3 Router ===");
    const approveTx = await lxon.approve(QUICKSWAP_V3_ROUTER, LXON_AMOUNT);
    console.log("Approval transaction:", approveTx.hash);
    await approveTx.wait();
    console.log("✅ LXON approved");

    // Simple Uniswap V2 approach using QuickSwap Factory
    const QUICKSWAP_FACTORY = "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab9D";
    
    console.log("\n=== Creating LXON/WMATIC Pair ===");
    const factoryAbi = [
      "function createPair(address tokenA, address tokenB) external returns (address pair)"
    ];
    const factory = await ethers.getContractAt(factoryAbi, QUICKSWAP_FACTORY);

    try {
      const createPairTx = await factory.createPair(LXON_ADDRESS, WMATIC);
      console.log("Create pair transaction:", createPairTx.hash);
      const receipt = await createPairTx.wait();
      console.log("✅ Pair created successfully");
      
      // Get pair address from event
      const pairAddress = receipt?.logs[0]?.address;
      console.log("Pair address:", pairAddress);
    } catch (error: any) {
      if (error.message.includes("already exists")) {
        console.log("⚠️  Pair already exists, fetching address...");
        
        const pairAbi = [
          "function getPair(address tokenA, address tokenB) external view returns (address)"
        ];
        const factoryWithGetPair = await ethers.getContractAt(pairAbi, QUICKSWAP_FACTORY);
        const pairAddress = await factoryWithGetPair.getPair(LXON_ADDRESS, WMATIC);
        console.log("Pair address:", pairAddress);
      } else {
        throw error;
      }
    }

    console.log("\n🎉 Setup complete!");
    console.log("You can now add liquidity via QuickSwap UI");
    console.log("Visit: https://quickswap.exchange/");

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
