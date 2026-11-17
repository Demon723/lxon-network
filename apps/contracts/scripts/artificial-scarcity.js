const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const LXON_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function balanceOf(address) view returns (uint256)",
  "function mint(address to) external returns (uint256)",
  "function burn(address to) external returns (uint256 amount0, uint256 amount1)"
];

async function main() {
  console.log("=== Artificial Scarcity: Reduce LXON in Liquidity ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, wallet);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, wallet);

  // Check current reserves
  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("\n=== Current State ===");
  console.log("WETH reserve:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));
  const currentPrice = Number(ethers.formatUnits(reserve0, wethDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals));
  console.log("Current price:", currentPrice, "WETH per LXON");
  console.log("Current price in USD:", currentPrice * 1.5, "USD per LXON");

  // Check wallet balances
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);
  const lpBalance = await pair.balanceOf(wallet.address);

  console.log("\n=== Wallet Balances ===");
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));
  console.log("LP tokens:", ethers.formatUnits(lpBalance, 18));

  // Step 1: Remove all liquidity
  console.log("\n=== Step 1: Remove All Liquidity ===");
  if (lpBalance > 0n) {
    try {
      const burnTx = await pair.burn(wallet.address);
      console.log("Burn transaction:", burnTx.hash);
      await burnTx.wait();
      console.log("✅ Liquidity removed - tokens returned to wallet");
    } catch (error) {
      console.error("❌ Burn failed:", error.message);
      return;
    }

    // Update balances after burn
    const newWethBalance = await weth.balanceOf(wallet.address);
    const newLxonBalance = await lxon.balanceOf(wallet.address);
    console.log("New WETH balance:", ethers.formatUnits(newWethBalance, wethDecimals));
    console.log("New LXON balance:", ethers.formatUnits(newLxonBalance, lxonDecimals));
  }

  // Step 2: Add liquidity with very little LXON (artificial scarcity)
  console.log("\n=== Step 2: Add Liquidity with Artificial Scarcity ===");

  const finalWethBalance = await weth.balanceOf(wallet.address);
  const finalLxonBalance = await lxon.balanceOf(wallet.address);

  console.log("Available WETH:", ethers.formatUnits(finalWethBalance, wethDecimals));
  console.log("Available LXON:", ethers.formatUnits(finalLxonBalance, lxonDecimals));

  // Target: Higher price through scarcity
  // Use a ratio that will give us a much higher price
  // Let's use 10M LXON and match it with a significant amount of WETH
  // To get $1.50 price (1 WETH per LXON), we need equal VALUE not equal amounts
  // WETH (18 decimals) vs LXON (6 decimals)
  // To get 1 WETH per LXON in price: we need the ratio to reflect this
  // Current WETH balance is ~16.9M, let's use half for liquidity
  const wethToUse = finalWethBalance / 2n;
  // To get $1.50/LXON, we need LXON amount = WETH amount (in value terms)
  // WETH in ETH units = WETH_amount / 10^18
  // LXON in LXON units = LXON_amount / 10^6
  // To get 1:1 price: WETH_amount / 10^18 = LXON_amount / 10^6
  // So: LXON_amount = WETH_amount / 10^12
  const lxonToUse = wethToUse / 1000000000000n; // Divide by 10^12

  console.log("\n=== Proposed Liquidity ===");
  console.log("LXON to add:", ethers.formatUnits(lxonToUse, lxonDecimals));
  console.log("WETH to add:", ethers.formatUnits(wethToUse, wethDecimals));
  console.log("Expected price:", "1 WETH per LXON = $1.50 per LXON");

  // Check if we have enough LXON
  let actualWethToUse = wethToUse;
  let actualLxonToUse = lxonToUse;

  if (lxonToUse > finalLxonBalance) {
    console.log("⚠️  Insufficient LXON for target price");
    console.log("Needed:", ethers.formatUnits(lxonToUse, lxonDecimals));
    console.log("Available:", ethers.formatUnits(finalLxonBalance, lxonDecimals));
    console.log("Adjusting to use available LXON");

    // Use available LXON and match WETH proportionally
    actualLxonToUse = finalLxonBalance / 2n;
    actualWethToUse = actualLxonToUse * 1000000000000n;

    console.log("Actual LXON to add:", ethers.formatUnits(actualLxonToUse, lxonDecimals));
    console.log("Actual WETH to add:", ethers.formatUnits(actualWethToUse, wethDecimals));

    const actualPrice = Number(ethers.formatUnits(actualWethToUse, wethDecimals)) / Number(ethers.formatUnits(actualLxonToUse, lxonDecimals));
    console.log("Actual expected price:", actualPrice, "WETH per LXON");
    console.log("Actual expected price in USD:", actualPrice * 1.5, "USD per LXON");
  }

  // Check if we have enough
  if (lxonToUse > finalLxonBalance) {
    console.log("⚠️  Insufficient LXON. Using available.");
    // Use available LXON
    const actualLxonToUse = finalLxonBalance / 2n;
    const actualWethToUse = actualLxonToUse;
    console.log("Actual LXON to add:", ethers.formatUnits(actualLxonToUse, lxonDecimals));
    console.log("Actual WETH to add:", ethers.formatUnits(actualWethToUse, wethDecimals));
  }

  // Approve
  console.log("\nApproving tokens...");
  await weth.approve(PAIR_ADDRESS, ethers.MaxUint256);
  await lxon.approve(PAIR_ADDRESS, ethers.MaxUint256);
  console.log("✅ Approved");

  // Transfer to pair
  await weth.transfer(PAIR_ADDRESS, actualWethToUse);
  await lxon.transfer(PAIR_ADDRESS, actualLxonToUse);
  console.log("✅ Tokens transferred to pair");

  // Mint LP tokens
  const mintTx = await pair.mint(wallet.address);
  console.log("Mint transaction:", mintTx.hash);
  await mintTx.wait();
  console.log("✅ LP tokens minted");

  // Verify
  console.log("\n=== Verification ===");
  const [newReserve0, newReserve1] = await pair.getReserves();
  console.log("New WETH reserve:", ethers.formatUnits(newReserve0, wethDecimals));
  console.log("New LXON reserve:", ethers.formatUnits(newReserve1, lxonDecimals));
  const newPrice = Number(ethers.formatUnits(newReserve0, wethDecimals)) / Number(ethers.formatUnits(newReserve1, lxonDecimals));
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price in USD:", newPrice * 1.5, "USD per LXON (assuming WETH = $1.50)");

  const totalLxon = Number(ethers.formatUnits(newReserve1, lxonDecimals));
  const marketCap = totalLxon * newPrice * 1.5;
  console.log("Market cap at this price: $" + marketCap.toFixed(0));

  console.log("\n⚠️  WARNING: Liquidity is very thin!");
  console.log("This will result in high price volatility.");
  console.log("Small trades will cause large price swings.");

  console.log("\n✅ Artificial scarcity implemented!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
