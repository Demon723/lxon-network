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
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function sync() external",
  "function skim(address to) external"
];

async function main() {
  console.log("=== Direct Transfer to Manipulate Price ===\n");

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

  console.log("\n=== Wallet Balances ===");
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));

  // Strategy: Send massive WETH to pair to increase price
  // Target: $2/LXON = 1.33 WETH per LXON (assuming WETH = $1.50)
  // To achieve this, need: WETH_reserve / LXON_reserve = 1.33
  // So: WETH_reserve = 1.33 * LXON_reserve
  // If we keep current LXON reserve, need to add WETH

  const targetPrice = 1.33; // 1.33 WETH per LXON = $2/LXON
  const currentLxonReserve = Number(ethers.formatUnits(reserve1, lxonDecimals));
  const targetWethReserve = currentLxonReserve * targetPrice;
  const currentWethReserve = Number(ethers.formatUnits(reserve0, wethDecimals));
  const wethToAdd = targetWethReserve - currentWethReserve;

  console.log("\n=== Calculation ===");
  console.log("Target price:", targetPrice, "WETH per LXON = $2/LXON");
  console.log("Current WETH reserve:", currentWethReserve);
  console.log("Target WETH reserve:", targetWethReserve);
  console.log("WETH to add:", wethToAdd);

  if (wethToAdd <= 0) {
    console.log("Already at or above target price!");
    return;
  }

  if (wethToAdd > Number(ethers.formatUnits(wethBalance, wethDecimals))) {
    console.log("⚠️  Insufficient WETH to reach target price");
    console.log("Adding all available WETH instead");
  }

  const wethToSend = wethToAdd > Number(ethers.formatUnits(wethBalance, wethDecimals)) 
    ? wethBalance 
    : ethers.parseUnits(wethToAdd.toString(), wethDecimals);

  console.log("Sending WETH to pair:", ethers.formatUnits(wethToSend, wethDecimals));

  // Send WETH to pair
  const tx = await weth.transfer(PAIR_ADDRESS, wethToSend);
  console.log("Transfer transaction:", tx.hash);
  await tx.wait();
  console.log("✅ WETH sent to pair");

  // Sync pair to update reserves
  console.log("\nSyncing pair...");
  await pair.sync();
  console.log("✅ Pair synced");

  // Verify
  console.log("\n=== Verification ===");
  const [newReserve0, newReserve1] = await pair.getReserves();
  console.log("New WETH reserve:", ethers.formatUnits(newReserve0, wethDecimals));
  console.log("New LXON reserve:", ethers.formatUnits(newReserve1, lxonDecimals));
  const newPrice = Number(ethers.formatUnits(newReserve0, wethDecimals)) / Number(ethers.formatUnits(newReserve1, lxonDecimals));
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price in USD:", newPrice * 1.5, "USD per LXON");

  const totalLxon = Number(ethers.formatUnits(newReserve1, lxonDecimals));
  const marketCap = totalLxon * newPrice * 1.5;
  console.log("Market cap at this price: $" + marketCap.toFixed(0));

  console.log("\n✅ Price manipulation attempted!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
