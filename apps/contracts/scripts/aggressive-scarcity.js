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
  "function decimals() view returns (uint8)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function skim(address to) external",
  "function sync() external"
];

async function main() {
  console.log("=== Artificial Scarcity: Remove LXON from Pair ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);
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

  const targetPrice = 1.33;
  const wethReserve = Number(ethers.formatUnits(reserve0, wethDecimals));
  const targetLxonReserve = Math.floor(wethReserve / targetPrice);

  console.log("\n=== Target ===");
  console.log("Target price:", targetPrice, "WETH per LXON = $2/LXON");
  console.log("Target LXON reserve:", targetLxonReserve);

  const pairLxonBalance = await lxon.balanceOf(PAIR_ADDRESS);
  console.log("Pair LXON balance:", ethers.formatUnits(pairLxonBalance, lxonDecimals));

  const lxonToRemove = pairLxonBalance - ethers.parseUnits(targetLxonReserve.toString(), lxonDecimals);

  if (lxonToRemove <= 0n) {
    console.log("\n❌ Not enough LXON in pair to achieve target price");
    return;
  }

  console.log("\n=== Removing LXON from Pair ===");
  console.log("LXON to remove:", ethers.formatUnits(lxonToRemove, lxonDecimals));

  try {
    const skimTx = await pair.skim(wallet.address);
    console.log("Skim transaction:", skimTx.hash);
    await skimTx.wait();
    console.log("✅ LXON removed from pair");
  } catch (error) {
    console.error("❌ Skim failed:", error.message);
    return;
  }

  await pair.sync();
  console.log("✅ Pair synced");

  const [newReserve0, newReserve1] = await pair.getReserves();
  const newPrice = Number(ethers.formatUnits(newReserve0, wethDecimals)) / Number(ethers.formatUnits(newReserve1, lxonDecimals));
  console.log("\n=== Verification ===");
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price in USD:", newPrice * 1.5, "USD per LXON");

  console.log("\n✅ Artificial scarcity implemented!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
