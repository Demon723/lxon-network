const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const LXON_1B_PRIVATE_KEY = process.env.LXON_1B_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const LXON_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external"
];

async function main() {
  console.log("=== Swap 2B LXON to WETH ===\n");

  if (!LXON_1B_PRIVATE_KEY) {
    console.log("❌ Need LXON_1B_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(LXON_1B_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("\n=== Current DEX Reserves ===");
  console.log("WETH reserve:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));

  const lxonBalance = await lxon.balanceOf(wallet.address);
  console.log("\n=== Wallet Balance ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));

  const swapAmount = ethers.parseUnits("2000000000", 6);
  console.log("\n=== Swap Calculation ===");
  console.log("Swap amount:", ethers.formatUnits(swapAmount, lxonDecimals), "LXON");

  if (swapAmount > reserve1) {
    console.log("\n⚠️  Swap amount exceeds DEX reserve!");
    console.log("DEX LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));
    console.log("Swap amount:", ethers.formatUnits(swapAmount, lxonDecimals));
    console.log("Ratio:", Number(ethers.formatUnits(swapAmount, lxonDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals)), "x");
    console.log("\nThis swap would drain the entire DEX.");
    console.log("Recommended: Swap smaller amount.");
    return;
  }

  console.log("\n=== Approving ===");
  const approveTx = await lxon.approve(PAIR_ADDRESS, swapAmount);
  console.log("Approve transaction:", approveTx.hash);
  await approveTx.wait();
  console.log("✅ Approved");

  const x = reserve1;
  const y = reserve0;
  const deltaX = swapAmount;
  const k = x * y;
  const deltaY = y - (k / (x + deltaX));

  console.log("\n=== Executing Swap ===");
  console.log("Expected WETH output:", ethers.formatUnits(deltaY, wethDecimals));

  try {
    const swapTx = await pair.swap(deltaY, 0n, wallet.address, "0x");
    console.log("Swap transaction:", swapTx.hash);
    await swapTx.wait();
    console.log("✅ Swap completed");
  } catch (error) {
    console.error("❌ Swap failed:", error.message);
    return;
  }

  const newWethBalance = await weth.balanceOf(wallet.address);
  const newLxonBalance = await lxon.balanceOf(wallet.address);

  console.log("\n=== Verification ===");
  console.log("New WETH balance:", ethers.formatUnits(newWethBalance, wethDecimals));
  console.log("New LXON balance:", ethers.formatUnits(newLxonBalance, lxonDecimals));

  console.log("\n✅ Swap completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
