import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Creating LXON/WMATIC Pair on QuickSwap (Polygon)\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // SushiSwap Factory (Polygon) - more reliable
  const SUSHISWAP_FACTORY = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
  const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

  // LXON address on Polygon
  const LXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  console.log("\n=== Configuration ===");
  console.log("SushiSwap Factory:", SUSHISWAP_FACTORY);
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

    // Create pair
    console.log("\n=== Creating LXON/WMATIC Pair ===");
    const factoryAbi = [
      "function createPair(address tokenA, address tokenB) external returns (address pair)",
      "function getPair(address tokenA, address tokenB) external view returns (address)"
    ];
    const factory = await ethers.getContractAt(factoryAbi, SUSHISWAP_FACTORY);

    // Check if pair already exists
    const existingPair = await factory.getPair(LXON_ADDRESS, WMATIC);
    if (existingPair !== ethers.ZeroAddress) {
      console.log("⚠️  Pair already exists!");
      console.log("Pair address:", existingPair);
      console.log("\n💡 You can add liquidity via SushiSwap UI:");
      console.log("   https://app.sushi.com/");
      console.log("   Search for LXON/WMATIC pair");
      return;
    }

    const createPairTx = await factory.createPair(LXON_ADDRESS, WMATIC);
    console.log("Create pair transaction:", createPairTx.hash);
    const receipt = await createPairTx.wait();
    console.log("✅ Pair created successfully!");
    
    // Get pair address
    const pairAddress = await factory.getPair(LXON_ADDRESS, WMATIC);
    console.log("Pair address:", pairAddress);

    console.log("\n=== Next Steps ===");
    console.log("1. Visit SushiSwap: https://app.sushi.com/");
    console.log("2. Connect your wallet (MetaMask)");
    console.log("3. Go to 'Pool' → 'Add Liquidity'");
    console.log("4. Select LXON and WMATIC");
    console.log("5. Add your desired liquidity amount");
    console.log("6. Set price ratio to achieve $1.50 per LXON");
    console.log("\n💡 For $1.50 per LXON (assuming MATIC = $0.50):");
    console.log("   1 LXON = 3 WMATIC");
    console.log("   Example: 10 LXON + 30 WMATIC = $30 TVL");

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
