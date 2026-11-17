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
  "function deposit() external payable",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function mint(address to) external returns (uint256)",
  "function burn(address to) external returns (uint256 amount0, uint256 amount1)"
];

async function main() {
  console.log("=== Adjust Liquidity to Achieve $1.50/LXON ===\n");

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

  // Check wallet balances
  const nativeBalance = await provider.getBalance(wallet.address);
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);

  console.log("Native LXON:", ethers.formatEther(nativeBalance));
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));

  // Step 1: Wrap native LXON (keep 100 for gas)
  console.log("\n=== Step 1: Wrap Native LXON ===");
  const gasReserve = ethers.parseEther("100");
  const wrapAmount = nativeBalance > gasReserve ? nativeBalance - gasReserve : 0n;

  if (wrapAmount > 0n) {
    console.log("Wrapping:", ethers.formatEther(wrapAmount), "native LXON");
    console.log("Keeping:", ethers.formatEther(gasReserve), "for gas");

    try {
      const wrapTx = await weth.deposit({ value: wrapAmount });
      console.log("Wrap transaction:", wrapTx.hash);
      await wrapTx.wait();
      console.log("✅ Wrapped successfully");
    } catch (error) {
      console.error("❌ Wrap failed:", error.message);
      return;
    }

    // Update WETH balance
    const newWethBalance = await weth.balanceOf(wallet.address);
    console.log("New WETH balance:", ethers.formatUnits(newWethBalance, wethDecimals));
  } else {
    console.log("No native LXON to wrap (already wrapped or insufficient)");
  }

  // Step 2: Burn all LP tokens to remove current liquidity
  console.log("\n=== Step 2: Remove Current Liquidity ===");
  const lpBalance = await pair.balanceOf(wallet.address);
  console.log("LP tokens to burn:", ethers.formatUnits(lpBalance, 18));

  if (lpBalance > 0n) {
    try {
      const burnTx = await pair.burn(wallet.address);
      console.log("Burn transaction:", burnTx.hash);
      await burnTx.wait();
      console.log("✅ Liquidity removed - tokens returned to wallet");
    } catch (error) {
      console.error("❌ Burn failed:", error.message);
      return;
    }
  }

  // Step 3: Add new liquidity with 1:1 ratio (WETH:LXON)
  console.log("\n=== Step 3: Add New Liquidity at 1:1 Ratio ===");
  const finalWethBalance = await weth.balanceOf(wallet.address);
  const finalLxonBalance = await lxon.balanceOf(wallet.address);

  console.log("WETH balance:", ethers.formatUnits(finalWethBalance, wethDecimals));
  console.log("LXON balance:", ethers.formatUnits(finalLxonBalance, lxonDecimals));

  // Use WETH as the limiting factor
  const wethToUse = finalWethBalance / 2n;
  // Convert WETH amount to LXON amount (1:1 ratio in value, but need to account for decimals)
  // WETH has 18 decimals, LXON has 6 decimals
  // To get 1:1 price, we need: WETH_amount / 10^18 = LXON_amount / 10^6
  // So: LXON_amount = WETH_amount * 10^12
  const lxonToUse = wethToUse * 1000000000000n; // 10^12

  console.log("WETH to add:", ethers.formatUnits(wethToUse, wethDecimals));
  console.log("LXON to add:", ethers.formatUnits(lxonToUse, lxonDecimals));

  // Check if we have enough LXON
  let actualWethToUse = wethToUse;
  let actualLxonToUse = lxonToUse;

  if (lxonToUse > finalLxonBalance) {
    console.log("⚠️  Insufficient LXON balance");
    console.log("Needed:", ethers.formatUnits(lxonToUse, lxonDecimals));
    console.log("Available:", ethers.formatUnits(finalLxonBalance, lxonDecimals));
    console.log("Using available LXON instead");
    // Use available LXON and match WETH
    actualLxonToUse = finalLxonBalance / 2n;
    actualWethToUse = actualLxonToUse / 1000000000000n;
    console.log("Adjusted WETH to add:", ethers.formatUnits(actualWethToUse, wethDecimals));
    console.log("Adjusted LXON to add:", ethers.formatUnits(actualLxonToUse, lxonDecimals));
  }

  // Approve
  console.log("\nApproving tokens...");
  await weth.approve(PAIR_ADDRESS, ethers.MaxUint256);
  await lxon.approve(PAIR_ADDRESS, ethers.MaxUint256);
  console.log("✅ Approved");

  // Transfer to pair
  await weth.transfer(PAIR_ADDRESS, actualWethToUse);
  await lxon.transfer(PAIR_ADDRESS, actualLxonToUse);
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

  console.log("\n✅ Liquidity adjusted successfully!");
  if (newPrice >= 0.9 && newPrice <= 1.1) {
    console.log("Price is now ~1 WETH per LXON = $1.50 per LXON (assuming WETH = $1.50)");
  } else {
    console.log("Price adjusted. Current price:", newPrice, "WETH per LXON");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
