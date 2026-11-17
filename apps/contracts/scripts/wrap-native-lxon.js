const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const WETH_ABI = [
  "function deposit() external payable",
  "function withdraw(uint256 amount) external",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  console.log("=== Wrap Native LXON into WETH ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deployer:", wallet.address);

  // Check native LXON balance
  const nativeBalance = await provider.getBalance(wallet.address);
  const nativeFormatted = Number(ethers.formatEther(nativeBalance));
  console.log("Native LXON balance:", nativeFormatted.toFixed(4));

  if (nativeBalance === 0n) {
    console.log("❌ No native LXON to wrap");
    return;
  }

  // Amount to wrap (wrap 1M LXON)
  const amountToWrap = ethers.parseEther("1000000");
  console.log("Amount to wrap:", ethers.formatEther(amountToWrap));

  if (nativeBalance < amountToWrap) {
    console.log("⚠️  Insufficient native LXON. Wrapping all available.");
    amountToWrap = nativeBalance;
  }

  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, wallet);

  console.log("\n=== Wrapping ===");
  try {
    const tx = await weth.deposit({ value: amountToWrap });
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Successfully wrapped native LXON into WETH");
  } catch (error) {
    console.error("❌ Failed to wrap:", error.message);
    return;
  }

  // Verify WETH balance
  const wethBalance = await weth.balanceOf(wallet.address);
  const wethDecimals = await weth.decimals();
  const wethFormatted = Number(ethers.formatUnits(wethBalance, wethDecimals));
  console.log("\n=== Verification ===");
  console.log("WETH balance:", wethFormatted.toFixed(4));
  console.log("✅ WETH created successfully");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
