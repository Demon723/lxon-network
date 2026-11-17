const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_1B_PRIVATE_KEY = process.env.LXON_1B_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const LXON_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function deposit() external payable",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function sync() external"
];

async function main() {
  console.log("=== Strategy: Acquire More WETH for Higher Price ===\n");

  if (!LXON_1B_PRIVATE_KEY) {
    console.log("❌ Need LXON_1B_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const deployerWallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);
  const lxon1BWallet = new ethers.Wallet(LXON_1B_PRIVATE_KEY, provider);

  console.log("Deployer:", deployerWallet.address);
  console.log("LXON 1B Address:", lxon1BWallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, lxon1BWallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, deployerWallet);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

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

  // Check balances
  const lxon1BBalance = await lxon.balanceOf(lxon1BWallet.address);
  const deployerNativeBalance = await provider.getBalance(deployerWallet.address);
  const wethBalance = await weth.balanceOf(deployerWallet.address);

  console.log("\n=== Balances ===");
  console.log("LXON 1B address LXON:", ethers.formatUnits(lxon1BBalance, lxonDecimals));
  console.log("Deployer native LXON:", ethers.formatEther(deployerNativeBalance));
  console.log("Deployer WETH:", ethers.formatUnits(wethBalance, wethDecimals));

  // Calculate WETH needed for $2/LXON
  const targetPrice = 1.33; // 1.33 WETH per LXON = $2/LXON
  const currentLxonReserve = Number(ethers.formatUnits(reserve1, lxonDecimals));
  const targetWethReserve = currentLxonReserve * targetPrice;
  const currentWethReserve = Number(ethers.formatUnits(reserve0, wethDecimals));
  const wethNeeded = targetWethReserve - currentWethReserve;

  console.log("\n=== Calculation ===");
  console.log("Target price:", targetPrice, "WETH per LXON = $2/LXON");
  console.log("WETH needed:", wethNeeded);

  // Check if we have enough native LXON to wrap
  const nativeLxonNeeded = wethNeeded; // 1:1 wrap
  console.log("Native LXON needed:", nativeLxonNeeded);
  console.log("Native LXON available:", Number(ethers.formatEther(deployerNativeBalance)));

  if (deployerNativeBalance === 0n) {
    console.log("\n❌ No native LXON available to wrap");
    console.log("Cannot achieve $2/LXON without more native LXON");
    return;
  }

  // Wrap native LXON
  console.log("\n=== Wrapping Native LXON ===");
  const gasReserve = ethers.parseEther("100");
  const wrapAmount = deployerNativeBalance > gasReserve ? deployerNativeBalance - gasReserve : 0n;

  if (wrapAmount === 0n) {
    console.log("No native LXON to wrap");
    return;
  }

  console.log("Wrapping:", ethers.formatEther(wrapAmount), "native LXON");
  const wrapTx = await weth.deposit({ value: wrapAmount });
  console.log("Wrap transaction:", wrapTx.hash);
  await wrapTx.wait();
  console.log("✅ Wrapped");

  // Send WETH to pair
  const newWethBalance = await weth.balanceOf(deployerWallet.address);
  console.log("\nNew WETH balance:", ethers.formatUnits(newWethBalance, wethDecimals));

  const wethToSend = newWethBalance;
  console.log("Sending WETH to pair:", ethers.formatUnits(wethToSend, wethDecimals));

  const transferTx = await weth.transfer(PAIR_ADDRESS, wethToSend);
  console.log("Transfer transaction:", transferTx.hash);
  await transferTx.wait();
  console.log("✅ WETH sent to pair");

  // Sync
  await pair.sync();
  console.log("✅ Pair synced");

  // Verify
  const [newReserve0, newReserve1] = await pair.getReserves();
  const newPrice = Number(ethers.formatUnits(newReserve0, wethDecimals)) / Number(ethers.formatUnits(newReserve1, lxonDecimals));
  console.log("\n=== Verification ===");
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price in USD:", newPrice * 1.5, "USD per LXON");

  console.log("\n✅ Complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
