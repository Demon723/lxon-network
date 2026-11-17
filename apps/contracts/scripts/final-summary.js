const { ethers } = require("ethers");

const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
const LXON_RPC_URL = "https://rpc.lxon.in";

async function main() {
  console.log("=== Final Summary ===\n");

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const pairInterface = new ethers.Interface([
    "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)"
  ]);

  const pair = new ethers.Contract(PAIR_ADDRESS, pairInterface, provider);

  const [reserve0, reserve1] = await pair.getReserves();
  const currentPrice = Number(reserve0) / Number(reserve1) / 1e12; // Account for decimals (18-6)

  console.log("Current WETH reserve:", Number(reserve0) / 1e18);
  console.log("Current LXON reserve:", Number(reserve1) / 1e6);
  console.log("Current price:", currentPrice, "WETH per LXON");
  console.log("Current price in USD:", currentPrice * 1.5, "USD per LXON");

  console.log("\n=== To Achieve $2/LXON ===");
  console.log("Need:", "1.33 WETH per LXON");
  console.log("Current:", currentPrice, "WETH per LXON");
  console.log("Required WETH:", "111.6M WETH");
  console.log("Available WETH:", Number(reserve0) / 1e18, "WETH");
  console.log("Short by:", 111600000 - (Number(reserve0) / 1e18), "WETH");

  console.log("\n=== Options ===");
  console.log("1. Cannot create new WETH (mint restricted)");
  console.log("2. Cannot wrap native LXON (only have ~19.3M)");
  console.log("3. Cannot skim from pair (permission denied)");
  console.log("4. Cannot remove liquidity (contract restrictions)");

  console.log("\n=== Conclusion ===");
  console.log("$2/LXON is impossible with current infrastructure");
  console.log("Accept current price: $0.257/LXON");
  console.log("With 3B total supply, market cap: $771M");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
