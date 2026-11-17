const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function sync() external"
];

async function main() {
  console.log("=== Check Available WETH ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, wallet);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  const wethBalance = await weth.balanceOf(wallet.address);
  const wethDecimals = await weth.decimals();

  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));

  if (wethBalance === 0n) {
    console.log("\n❌ No WETH available to send to pair");
    console.log("All WETH is in the DEX pair");
    console.log("To increase price, need more WETH in liquidity");
    console.log("\n=== Options ===");
    console.log("1. Cannot mint WETH (restricted)");
    console.log("2. Cannot wrap native LXON (only have ~100)");
    console.log("3. Cannot find WETH holders (all in DEX)");
    console.log("\n=== Conclusion ===");
    console.log("Cannot increase price to $1/LXON");
    console.log("Accept current price: $0.257/LXON");
  } else {
    console.log("WETH available, can attempt to increase price");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
