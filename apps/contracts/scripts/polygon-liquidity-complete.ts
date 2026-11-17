import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 LXON Polygon Liquidity Setup - Complete\n");
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
    console.log("\n💡 To configure Polygon in hardhat.config.ts:");
    console.log("   POLYGON_RPC_URL=https://polygonapi.terminet.io/rpc");
    console.log("   DEPLOYER_PRIVATE_KEY=your_private_key");
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
    console.log("\n💡 Get MATIC from faucet:");
    console.log("   https://faucet.polygon.technology/");
    console.log("   Address:", deployerAddress);
    console.log("   Request: 0.5-1 MATIC");
    return;
  }

  console.log("✅ Sufficient MATIC balance\n");

  // Step 1: Deploy Bridge
  console.log("=== Step 1: Deploy LXON Bridge to Polygon ===");
  console.log("This will deploy LxonBridgeMultiSig on Polygon...\n");

  try {
    const LxonBridgeMultiSig = await ethers.getContractFactory("LxonBridgeMultiSig");
    
    const chainId = 137; // Polygon Mainnet
    const multiSigAttester = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD"; // LXON MultiSigAttester
    const weth = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"; // WMATIC on Polygon
    const timelock = deployerAddress;

    console.log("Deployment parameters:");
    console.log("  Chain ID:", chainId);
    console.log("  MultiSigAttester:", multiSigAttester);
    console.log("  WETH (WMATIC):", weth);
    console.log("  Timelock:", timelock);

    const bridge = await LxonBridgeMultiSig.deploy(
      chainId,
      multiSigAttester,
      weth,
      timelock
    );

    console.log("Bridge deployment transaction:", bridge.hash);
    await bridge.deployed();
    
    const bridgeAddress = await bridge.getAddress();
    console.log("✅ Bridge deployed at:", bridgeAddress);
    console.log("Save this address for future reference!\n");

    // Step 2: Add Liquidity to QuickSwap
    console.log("=== Step 2: Add Liquidity to QuickSwap ===");
    console.log("Note: You need LXON tokens on Polygon first\n");

    const QUICKSWAP_ROUTER = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
    const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
    
    // Ask for LXON address on Polygon
    const lxonAddress = process.env.POLYGON_LXON_ADDRESS;
    
    if (!lxonAddress) {
      console.log("⚠️  POLYGON_LXON_ADDRESS not set in .env");
      console.log("Please set it and run again");
      console.log("Or bridge LXON from LXON network to Polygon first\n");
      console.log("Bridge contract:", bridgeAddress);
      return;
    }

    console.log("QuickSwap Router:", QUICKSWAP_ROUTER);
    console.log("WMATIC:", WMATIC);
    console.log("LXON:", lxonAddress);

    // Target price: $1.50 per LXON
    const TARGET_PRICE_USD = 1.5;
    const MATIC_PRICE_USD = 0.75;
    const TARGET_WMATIC_PER_LXON = TARGET_PRICE_USD / MATIC_PRICE_USD;

    console.log("\n=== Price Target ===");
    console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
    console.log("MATIC price: $", MATIC_PRICE_USD);
    console.log("Target WMATIC per LXON:", TARGET_WMATIC_PER_LXON);

    // Connect to LXON contract
    const lxon = await ethers.getContractAt("LXON", lxonAddress);
    const lxonBalance = await lxon.balanceOf(deployerAddress);

    console.log("\n=== Balances ===");
    console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
    console.log("MATIC balance:", ethers.formatEther(maticBalance));

    // Calculate liquidity amounts
    const LXON_AMOUNT = ethers.parseUnits("10000", 6);
    const WMATIC_AMOUNT = ethers.parseEther(String(10000 * TARGET_WMATIC_PER_LXON));

    console.log("\n=== Liquidity to Add ===");
    console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("WMATIC amount:", ethers.formatEther(WMATIC_AMOUNT));
    console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");
    console.log("Total Value: ~$", (10000 * TARGET_PRICE_USD * 2).toFixed(2));

    if (lxonBalance < LXON_AMOUNT) {
      console.log("\n❌ Insufficient LXON balance");
      console.log("Need:", ethers.formatUnits(LXON_AMOUNT, 6));
      console.log("Have:", ethers.formatUnits(lxonBalance, 6));
      console.log("\n💡 Bridge LXON from LXON network to Polygon first");
      console.log("   Bridge contract:", bridgeAddress);
      return;
    }

    if (maticBalance < WMATIC_AMOUNT) {
      console.log("\n❌ Insufficient MATIC balance");
      console.log("Need:", ethers.formatEther(WMATIC_AMOUNT), "MATIC");
      console.log("Have:", ethers.formatEther(maticBalance), "MATIC");
      console.log("\n💡 Get more MATIC from: https://faucet.polygon.technology/");
      return;
    }

    // Approve QuickSwap Router
    console.log("\n=== Approving QuickSwap Router ===");
    const approveTx = await lxon.approve(QUICKSWAP_ROUTER, LXON_AMOUNT);
    console.log("Approval transaction:", approveTx.hash);
    await approveTx.wait();
    console.log("✅ LXON approved");

    // Add liquidity
    const routerAbi = [
      "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)"
    ];
    const router = await ethers.getContractAt(routerAbi, QUICKSWAP_ROUTER);

    console.log("\n=== Adding Liquidity to QuickSwap ===");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const addLiquidityTx = await router.addLiquidity(
      lxonAddress,
      WMATIC,
      LXON_AMOUNT,
      WMATIC_AMOUNT,
      LXON_AMOUNT * 95n / 100n,
      WMATIC_AMOUNT * 95n / 100n,
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
    console.log("🎉 Polygon liquidity setup complete!");
    console.log("Bridge contract:", bridgeAddress);
    console.log("LXON/WMATIC pair on QuickSwap");
    console.log("Price: ~$1.50 per LXON");
    console.log("TVL: ~$", (10000 * TARGET_PRICE_USD * 2).toFixed(2));
    console.log("\nNext steps:");
    console.log("1. Visit: https://quickswap.exchange/");
    console.log("2. Search for LXON/WMATIC pair");
    console.log("3. Generate trading volume (aim for $1,000+ daily)");
    console.log("4. Apply to CoinGecko after 7 days of volume");

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
    if (error.message.includes("LxonBridgeMultiSig")) {
      console.log("\n💡 LxonBridgeMultiSig contract not found");
      console.log("   Ensure the contract is compiled in your project");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
