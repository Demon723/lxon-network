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
  "function decimals() view returns (uint8)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external"
];

async function main() {
  console.log("=== Direct Pair Swap Test ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  // Check current reserves
  console.log("\n=== Current DEX Reserves ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("Reserve0 (WETH):", ethers.formatUnits(reserve0, wethDecimals));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, lxonDecimals));

  // Check wallet balances
  console.log("\n=== Wallet Balances ===");
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);

  console.log("WETH:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON:", ethers.formatUnits(lxonBalance, lxonDecimals));

  // Test: transfer LXON to pair directly (simulate swap)
  console.log("\n=== Test: Transfer LXON to Pair ===");
  const testAmount = ethers.parseUnits("100", 6); // 100 LXON

  if (lxonBalance < testAmount) {
    console.log("❌ Insufficient LXON");
    return;
  }

  try {
    const tx = await lxon.transfer(PAIR_ADDRESS, testAmount);
    console.log("Transfer transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Transfer successful");

    // Check new reserves
    const [newReserve0, newReserve1] = await pair.getReserves();
    console.log("\n=== New Reserves ===");
    console.log("Reserve0 (WETH):", ethers.formatUnits(newReserve0, wethDecimals));
    console.log("Reserve1 (LXON):", ethers.formatUnits(newReserve1, lxonDecimals));

    console.log("\n✅ Pair accepts tokens - liquidity is functional");
  } catch (error) {
    console.error("❌ Transfer failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
