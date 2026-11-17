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
  "function burn(address to) external returns (uint256 amount0, uint256 amount1)",
  "function sync() external"
];

async function main() {
  console.log("=== Simple Artificial Scarcity ===\n");

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

  // Check wallet balances
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);

  console.log("\n=== Wallet Balances ===");
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));

  // Step 1: Send WETH to pair to increase price
  console.log("\n=== Step 1: Send WETH to Pair ===");
  const wethToSend = wethBalance / 2n;
  console.log("Sending WETH to pair:", ethers.formatUnits(wethToSend, wethDecimals));

  await weth.transfer(PAIR_ADDRESS, wethToSend);
  console.log("✅ WETH sent to pair");

  // Step 2: Sync pair
  console.log("\n=== Step 2: Sync Pair ===");
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

  console.log("\n✅ Liquidity adjusted!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
