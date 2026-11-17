import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Adding Liquidity to LXON/WETH Pair (LXON Network)\n");
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
    console.log("\n⚠️  WARNING: This script is for LXON Network (Chain ID 724)");
    console.log("Current network is not LXON Network");
    console.log("Please ensure you're using --network lxonMainnet");
    return;
  }

  // LXON network DEX addresses
  const UNISWAP_ROUTER = "0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602";
  const WETH = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
  const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

  console.log("\n=== Configuration ===");
  console.log("Uniswap Router:", UNISWAP_ROUTER);
  console.log("WETH:", WETH);
  console.log("LXON:", LXON_ADDRESS);

  // Connect to LXON contract
  try {
    const lxon = await ethers.getContractAt("LXON", LXON_ADDRESS);
    const lxonBalance = await lxon.balanceOf(deployerAddress);
    const ethBalance = await ethers.provider.getBalance(deployerAddress);

    console.log("\n=== Balances ===");
    console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
    console.log("ETH balance:", ethers.formatEther(ethBalance));

    // Check WETH balance
    const weth = await ethers.getContractAt("IWETH", WETH);
    const wethBalance = await weth.balanceOf(deployerAddress);
    console.log("WETH balance:", ethers.formatEther(wethBalance));

    // Calculate liquidity amounts
    // Target price: $1.50 per LXON
    const TARGET_PRICE_USD = 1.5;
    const ETH_PRICE_USD = 3000; // Approximate ETH price
    const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD;

    console.log("\n=== Price Target ===");
    console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
    console.log("ETH price: $", ETH_PRICE_USD);
    console.log("Target WETH per LXON:", TARGET_WETH_PER_LXON);

    // Use 1,000 LXON for liquidity
    const LXON_AMOUNT = ethers.parseUnits("1000", 6);
    const WETH_AMOUNT = ethers.parseEther(String(1000 * TARGET_WETH_PER_LXON));

    console.log("\n=== Liquidity to Add ===");
    console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("WETH amount:", ethers.formatEther(WETH_AMOUNT));
    console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");
    console.log("Total Value: ~$", (1000 * TARGET_PRICE_USD * 2).toFixed(2));

    if (lxonBalance < LXON_AMOUNT) {
      console.log("\n❌ Insufficient LXON balance");
      console.log("Need:", ethers.formatUnits(LXON_AMOUNT, 6));
      console.log("Have:", ethers.formatUnits(lxonBalance, 6));
      return;
    }

    // Check if we need to wrap ETH to WETH
    if (wethBalance < WETH_AMOUNT) {
      if (ethBalance < WETH_AMOUNT) {
        console.log("\n❌ Insufficient ETH balance");
        console.log("Need:", ethers.formatEther(WETH_AMOUNT), "ETH");
        console.log("Have:", ethers.formatEther(ethBalance), "ETH");
        console.log("\n💡 You need to wrap ETH to WETH first or deposit more ETH");
        return;
      }

      console.log("\n=== Wrapping ETH to WETH ===");
      const wrapTx = await weth.deposit({ value: WETH_AMOUNT });
      console.log("Wrap transaction:", wrapTx.hash);
      await wrapTx.wait();
      console.log("✅ ETH wrapped to WETH");
    }

    // Approve Uniswap Router to spend LXON
    console.log("\n=== Approving Uniswap Router ===");
    const approveTx = await lxon.approve(UNISWAP_ROUTER, LXON_AMOUNT);
    console.log("Approval transaction:", approveTx.hash);
    await approveTx.wait();
    console.log("✅ LXON approved");

    // Approve Uniswap Router to spend WETH
    console.log("\n=== Approving WETH ===");
    const approveWethTx = await weth.approve(UNISWAP_ROUTER, WETH_AMOUNT);
    console.log("WETH approval transaction:", approveWethTx.hash);
    await approveWethTx.wait();
    console.log("✅ WETH approved");

    // Get Uniswap Router interface
    const routerAbi = [
      "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)"
    ];
    const router = await ethers.getContractAt(routerAbi, UNISWAP_ROUTER);

    // Add liquidity to Uniswap
    console.log("\n=== Adding Liquidity to Uniswap ===");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const addLiquidityTx = await router.addLiquidity(
      LXON_ADDRESS,
      WETH,
      LXON_AMOUNT,
      WETH_AMOUNT,
      LXON_AMOUNT * 95n / 100n,  // 5% slippage tolerance
      WETH_AMOUNT * 95n / 100n, // 5% slippage tolerance
      deployerAddress,
      deadline
    );

    console.log("Liquidity transaction:", addLiquidityTx.hash);
    const receipt = await addLiquidityTx.wait();

    console.log("\n✅ Liquidity added successfully!");
    console.log("Transaction hash:", receipt?.hash);
    console.log("Gas used:", receipt?.gasUsed.toString());

    console.log("\n=== Success ===");
    console.log("Liquidity added to Uniswap on LXON network");
    console.log("Price should be approximately $1.50 per LXON");
    console.log("TVL: ~$", (1000 * TARGET_PRICE_USD * 2).toFixed(2));
    console.log("\n🎉 You can now trade LXON on the LXON network!");
    console.log("Pair Address: 0x3aD52bD5996f16C902225b0d9C111fafE6B77786");

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
