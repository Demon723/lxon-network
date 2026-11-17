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
  "function transfer(address to, uint256 amount) external returns (bool)"
];

async function main() {
  console.log("=== Calculate Liquidity Needed for $1.50/LXON ===\n");

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, provider);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  // Current reserves
  const [reserve0, reserve1] = await pair.getReserves();
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  const currentWeth = Number(ethers.formatUnits(reserve0, wethDecimals));
  const currentLxon = Number(ethers.formatUnits(reserve1, lxonDecimals));

  console.log("=== Current Liquidity ===");
  console.log("WETH reserve:", currentWeth);
  console.log("LXON reserve:", currentLxon);
  console.log("Current price:", currentWeth / currentLxon, "WETH per LXON");

  // Target price: $1.50 per LXON
  // Assuming WETH = $1.50, we need 1 WETH per LXON
  const targetPrice = 1.0; // 1 WETH per LXON

  console.log("\n=== Target Price ===");
  console.log("Target: $1.50 per LXON");
  console.log("Assuming WETH = $1.50");
  console.log("Target price:", targetPrice, "WETH per LXON");

  // Option 1: Keep current LXON amount, add massive WETH
  const option1WethNeeded = currentLxon * targetPrice;
  console.log("\n=== Option 1: Keep " + currentLxon + " LXON in liquidity ===");
  console.log("WETH needed:", option1WethNeeded);
  console.log("WETH to add:", option1WethNeeded - currentWeth);
  console.log("Current WETH wallet balance:", Number(ethers.formatUnits(await weth.balanceOf(wallet.address), wethDecimals)));

  // Option 2: Reduce LXON in liquidity to match available WETH
  const walletWeth = Number(ethers.formatUnits(await weth.balanceOf(wallet.address), wethDecimals));
  const totalWethAvailable = currentWeth + walletWeth;
  const option2LxonNeeded = totalWethAvailable / targetPrice;
  console.log("\n=== Option 2: Reduce LXON to match available WETH ===");
  console.log("Total WETH available:", totalWethAvailable);
  console.log("LXON to keep in liquidity:", option2LxonNeeded);
  console.log("LXON to remove:", currentLxon - option2LxonNeeded);

  // Option 3: Wrap all native LXON and add to liquidity
  const nativeBalance = await provider.getBalance(wallet.address);
  const nativeFormatted = Number(ethers.formatEther(nativeBalance));
  console.log("\n=== Option 3: Wrap all native LXON ===");
  console.log("Native LXON available:", nativeFormatted);
  console.log("Total WETH after wrapping:", walletWeth + nativeFormatted);
  const option3Lxon = (walletWeth + nativeFormatted) / targetPrice;
  console.log("LXON to keep in liquidity:", option3Lxon);
  console.log("LXON to remove:", currentLxon - option3Lxon);

  // Option 4: Transfer more LXON from 1B address and wrap native
  const lxon1BAddress = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";
  const lxon1BBalance = Number(ethers.formatUnits(await lxon.balanceOf(lxon1BAddress), lxonDecimals));
  console.log("\n=== Option 4: Use all available resources ===");
  console.log("LXON from 1B address:", lxon1BBalance);
  console.log("Native LXON:", nativeFormatted);
  console.log("Total WETH after wrapping:", walletWeth + nativeFormatted);
  const option4Lxon = (walletWeth + nativeFormatted) / targetPrice;
  console.log("LXON to keep in liquidity:", option4Lxon);
  console.log("Total LXON in ecosystem:", currentLxon + option4Lxon);
  console.log("Market cap at $1.50:", "$" + ((currentLxon + option4Lxon) * 1.5).toFixed(0));

  console.log("\n=== Recommendation ===");
  console.log("Option 4 is best: Use all native LXON, keep limited LXON in liquidity");
  console.log("This creates artificial scarcity and supports higher price");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
