const { ethers } = require("ethers");
const fs = require("fs");
require("dotenv").config();

// Addresses
const YOUR_WALLET = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"; // Has the WETH
const DEPLOYER = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
const ORIGINAL_WETH = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

async function main() {
  console.log("=== Transfer WETH from Your Wallet to Deployer ===\n");

  const deployerKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const deployer = new ethers.Wallet(deployerKey, provider);

  console.log("Deployer:", deployer.address);

  const wethToken = new ethers.Contract(ORIGINAL_WETH, ERC20_ABI, provider);

  // Check WETH balance in your wallet
  console.log("\n=== Checking WETH Balance ===");
  const wethBalance = await wethToken.balanceOf(YOUR_WALLET);
  console.log("Your wallet:", YOUR_WALLET);
  console.log("WETH balance:", ethers.formatEther(wethBalance));

  if (wethBalance === 0n) {
    console.log("\n❌ No WETH balance in your wallet");
    return;
  }

  console.log("✅ Found WETH:", ethers.formatEther(wethBalance));

  // Ask for approval
  console.log("\n=== Transfer Action ===");
  console.log("Transfer 100 WETH from your wallet to deployer");
  console.log("Your wallet:", YOUR_WALLET);
  console.log("Deployer:", DEPLOYER);
  console.log("Amount: 100 WETH");
  console.log("\n⚠️  This requires YOUR_WALLET_PRIVATE_KEY in .env");
  console.log("Please add YOUR_WALLET_PRIVATE_KEY to .env and run again");
  console.log("Or transfer manually via MetaMask");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
