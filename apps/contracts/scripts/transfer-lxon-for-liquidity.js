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
  "function mint(address to) external returns (uint256)"
];

async function main() {
  console.log("=== Transfer LXON from 1B Address for Liquidity ===\n");

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
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  // Check balances
  const lxon1BBalance = await lxon.balanceOf(lxon1BWallet.address);
  const deployerWethBalance = await weth.balanceOf(deployerWallet.address);
  const lxonDecimals = await lxon.decimals();
  const wethDecimals = await weth.decimals();

  console.log("\n=== Current Balances ===");
  console.log("LXON 1B address:", ethers.formatUnits(lxon1BBalance, lxonDecimals));
  console.log("Deployer WETH:", ethers.formatUnits(deployerWethBalance, wethDecimals));

  // Calculate how much LXON needed to match WETH at 1:1 price
  // To get 1 WETH per LXON, we need: WETH_amount / 10^18 = LXON_amount / 10^6
  // So: LXON_amount = WETH_amount * 10^12
  const wethToUse = deployerWethBalance / 2n;
  const lxonNeeded = wethToUse * 1000000000000n; // 10^12

  console.log("\n=== Calculation ===");
  console.log("WETH to use for liquidity:", ethers.formatUnits(wethToUse, wethDecimals));
  console.log("LXON needed for 1:1 price:", ethers.formatUnits(lxonNeeded, lxonDecimals));

  // Transfer LXON from 1B address to deployer
  console.log("\n=== Transfer LXON from 1B Address ===");
  const lxonToTransfer = lxonNeeded;

  if (lxonToTransfer > lxon1BBalance) {
    console.log("⚠️  Insufficient LXON in 1B address");
    console.log("Needed:", ethers.formatUnits(lxonToTransfer, lxonDecimals));
    console.log("Available:", ethers.formatUnits(lxon1BBalance, lxonDecimals));
    console.log("Transferring all available LXON");
  }

  const actualTransfer = lxonToTransfer > lxon1BBalance ? lxon1BBalance : lxonToTransfer;

  try {
    const tx = await lxon.transfer(deployerWallet.address, actualTransfer);
    console.log("Transfer transaction:", tx.hash);
    await tx.wait();
    console.log("✅ LXON transferred");
  } catch (error) {
    console.error("❌ Transfer failed:", error.message);
    return;
  }

  // Verify new balance
  const newDeployerLxonBalance = await lxon.balanceOf(deployerWallet.address);
  console.log("\nNew deployer LXON balance:", ethers.formatUnits(newDeployerLxonBalance, lxonDecimals));

  console.log("\n✅ Ready to add liquidity");
  console.log("Run adjust-liquidity-for-price.js again to complete the process");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
