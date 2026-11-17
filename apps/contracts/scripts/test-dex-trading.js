const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const ROUTER_ADDRESS = "0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
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
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)"
];

const ROUTER_ABI = [
  "function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)",
  "function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts)"
];

async function main() {
  console.log("=== Test DEX Trading ===\n");

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
  const router = new ethers.Contract(ROUTER_ADDRESS, ROUTER_ABI, wallet);

  // Check current reserves
  console.log("\n=== Current DEX Reserves ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("WETH reserve:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));

  // Check wallet balances
  console.log("\n=== Wallet Balances ===");
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);

  console.log("WETH:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON:", ethers.formatUnits(lxonBalance, lxonDecimals));

  // Test swap calculation
  console.log("\n=== Test Swap Calculation ===");
  const swapAmount = ethers.parseUnits("1000", 6); // 1000 LXON
  const path = [LXON_ADDRESS, WETH_ADDRESS];

  const amountsOut = await router.getAmountsOut(swapAmount, path);
  console.log("Swap 1000 LXON for:", ethers.formatUnits(amountsOut[1], wethDecimals), "WETH");

  // Execute small test swap
  console.log("\n=== Execute Test Swap ===");
  const testAmount = ethers.parseUnits("100", 6); // 100 LXON

  if (lxonBalance < testAmount) {
    console.log("❌ Insufficient LXON for test swap");
    return;
  }

  // Approve router
  console.log("Approving router...");
  const approveTx = await lxon.approve(ROUTER_ADDRESS, ethers.MaxUint256);
  await approveTx.wait();
  console.log("✅ Approved");

  // Execute swap
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour
  const minOut = amountsOut[1] * 95n / 100n; // 5% slippage

  try {
    const swapTx = await router.swapExactTokensForTokens(
      testAmount,
      minOut,
      path,
      wallet.address,
      deadline
    );
    console.log("Swap transaction:", swapTx.hash);
    await swapTx.wait();
    console.log("✅ Swap successful");
  } catch (error) {
    console.error("❌ Swap failed:", error.message);
    return;
  }

  // Verify new balances
  console.log("\n=== Post-Swap Balances ===");
  const newWethBalance = await weth.balanceOf(wallet.address);
  const newLxonBalance = await lxon.balanceOf(wallet.address);

  console.log("WETH:", ethers.formatUnits(newWethBalance, wethDecimals));
  console.log("LXON:", ethers.formatUnits(newLxonBalance, lxonDecimals));

  const wethReceived = newWethBalance - wethBalance;
  const lxonSpent = lxonBalance - newLxonBalance;

  console.log("\n=== Summary ===");
  console.log("LXON spent:", ethers.formatUnits(lxonSpent, lxonDecimals));
  console.log("WETH received:", ethers.formatUnits(wethReceived, wethDecimals));

  console.log("\n✅ DEX trading is working!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
