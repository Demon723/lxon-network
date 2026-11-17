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
  "function mint(address to) external returns (uint256)",
  "function burn(address to) external returns (uint256 amount0, uint256 amount1)",
  "function balanceOf(address) view returns (uint256)"
];

async function main() {
  console.log("=== Achieve $1/LXON via Liquidity Removal ===\n");

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

  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("\n=== Current State ===");
  console.log("WETH reserve:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));
  const currentPrice = Number(ethers.formatUnits(reserve0, wethDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals));
  console.log("Current price:", currentPrice, "WETH per LXON");
  console.log("Current price in USD:", currentPrice * 1.5, "USD per LXON");

  const targetPrice = 0.667;
  const wethReserve = Number(ethers.formatUnits(reserve0, wethDecimals));
  const targetLxonReserve = Math.floor(wethReserve / targetPrice);

  console.log("\n=== Target: $1/LXON ===");
  console.log("Target price:", targetPrice, "WETH per LXON = $1/LXON");
  console.log("Target LXON reserve:", targetLxonReserve);

  // Just send LXON to pair to increase price
  console.log("\n=== Strategy: Send WETH to Pair ===");
  const wethBalance = await weth.balanceOf(wallet.address);
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));

  if (wethBalance === 0n) {
    console.log("❌ No WETH available");
    console.log("All WETH is in the DEX pair");
    console.log("Cannot increase price without more WETH");
    return;
  }

  const wethToSend = wethBalance;
  console.log("Sending WETH to pair:", ethers.formatUnits(wethToSend, wethDecimals));

  const tx = await weth.transfer(PAIR_ADDRESS, wethToSend);
  console.log("Transfer transaction:", tx.hash);
  await tx.wait();
  console.log("✅ WETH sent to pair");

  // Sync
  const pairInterface = new ethers.Interface(["function sync() external"]);
  const pairSync = new ethers.Contract(PAIR_ADDRESS, pairInterface, wallet);
  await pairSync.sync();
  console.log("✅ Pair synced");

  // Verify
  const [newReserve0, newReserve1] = await pair.getReserves();
  const newPrice = Number(ethers.formatUnits(newReserve0, wethDecimals)) / Number(ethers.formatUnits(newReserve1, lxonDecimals));
  console.log("\n=== Verification ===");
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
