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
  "function burn(address to) external returns (uint256 amount0, uint256 amount1)"
];

async function main() {
  console.log("=== Add WETH to Increase Price ===\n");

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

  // Step 1: Remove liquidity
  console.log("\n=== Step 1: Remove Existing Liquidity ===");
  const lpBalance = await pair.balanceOf(wallet.address);
  console.log("LP tokens:", ethers.formatUnits(lpBalance, 18));

  if (lpBalance > 0n) {
    const burnTx = await pair.burn(wallet.address);
    console.log("Burn transaction:", burnTx.hash);
    await burnTx.wait();
    console.log("✅ Liquidity removed");
  }

  // Step 2: Add liquidity with all WETH and small amount of LXON
  console.log("\n=== Step 2: Add Liquidity with All WETH ===");

  const finalWethBalance = await weth.balanceOf(wallet.address);
  const finalLxonBalance = await lxon.balanceOf(wallet.address);

  console.log("Available WETH:", ethers.formatUnits(finalWethBalance, wethDecimals));
  console.log("Available LXON:", ethers.formatUnits(finalLxonBalance, lxonDecimals));

  // Use all WETH and 10M LXON for higher price
  const lxonToUse = ethers.parseUnits("10000000", 6); // 10M LXON
  const wethToUse = finalWethBalance; // Use all WETH

  console.log("\n=== Proposed Liquidity ===");
  console.log("LXON to add:", ethers.formatUnits(lxonToUse, lxonDecimals));
  console.log("WETH to add:", ethers.formatUnits(wethToUse, wethDecimals));

  const expectedPrice = Number(ethers.formatUnits(wethToUse, wethDecimals)) / Number(ethers.formatUnits(lxonToUse, lxonDecimals));
  console.log("Expected price:", expectedPrice, "WETH per LXON");
  console.log("Expected price in USD:", expectedPrice * 1.5, "USD per LXON");

  // Approve
  console.log("\nApproving tokens...");
  await weth.approve(PAIR_ADDRESS, ethers.MaxUint256);
  await lxon.approve(PAIR_ADDRESS, ethers.MaxUint256);
  console.log("✅ Approved");

  // Transfer to pair
  await weth.transfer(PAIR_ADDRESS, wethToUse);
  await lxon.transfer(PAIR_ADDRESS, lxonToUse);
  console.log("✅ Tokens transferred to pair");

  // Mint LP tokens
  const mintTx = await pair.mint(wallet.address);
  console.log("Mint transaction:", mintTx.hash);
  await mintTx.wait();
  console.log("✅ LP tokens minted");

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

  console.log("\n✅ Liquidity adjusted!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
