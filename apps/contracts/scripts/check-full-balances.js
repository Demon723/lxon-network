const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const YOUR_WALLET = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)"
];

async function main() {
  console.log("=== Full Token Balance Check ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const weth = new ethers.Contract(WETH_ADDRESS, ERC20_ABI, provider);
  const lxon = new ethers.Contract(LXON_ADDRESS, ERC20_ABI, provider);

  // WETH info
  const wethDecimals = await weth.decimals();
  const wethSymbol = await weth.symbol();
  const wethTotalSupply = await weth.totalSupply();
  const wethSupplyFormatted = Number(ethers.formatUnits(wethTotalSupply, wethDecimals));

  console.log(`${wethSymbol} Token Info:`);
  console.log(`  Total Supply: ${wethSupplyFormatted.toFixed(4)} ${wethSymbol}`);
  console.log(`  Decimals: ${wethDecimals}\n`);

  // LXON info
  const lxonDecimals = await lxon.decimals();
  const lxonSymbol = await lxon.symbol();
  const lxonTotalSupply = await lxon.totalSupply();
  const lxonSupplyFormatted = Number(ethers.formatUnits(lxonTotalSupply, lxonDecimals));

  console.log(`${lxonSymbol} Token Info:`);
  console.log(`  Total Supply: ${lxonSupplyFormatted.toFixed(4)} ${lxonSymbol}`);
  console.log(`  Decimals: ${lxonDecimals}\n`);

  // Your wallet balances
  const wethBalance = await weth.balanceOf(YOUR_WALLET);
  const lxonBalance = await lxon.balanceOf(YOUR_WALLET);

  const wethFormatted = Number(ethers.formatUnits(wethBalance, wethDecimals));
  const lxonFormatted = Number(ethers.formatUnits(lxonBalance, lxonDecimals));

  console.log(`Your Wallet (${YOUR_WALLET}):`);
  console.log(`  ${wethSymbol}: ${wethFormatted.toFixed(4)}`);
  console.log(`  ${lxonSymbol}: ${lxonFormatted.toFixed(4)}\n`);

  // Check native balance
  const nativeBalance = await provider.getBalance(YOUR_WALLET);
  const nativeFormatted = Number(ethers.formatEther(nativeBalance));
  console.log(`  Native (LXON): ${nativeFormatted.toFixed(4)}\n`);

  // Summary
  console.log("=== Summary ===");
  console.log(`WETH Total Supply: ${wethSupplyFormatted.toFixed(4)}`);
  console.log(`Your WETH Balance: ${wethFormatted.toFixed(4)}`);
  console.log(`Your LXON Balance: ${lxonFormatted.toFixed(4)}`);
  console.log(`Your Native Balance: ${nativeFormatted.toFixed(4)}`);

  if (wethFormatted === 0) {
    console.log("\n⚠️  WARNING: You have 0 WETH balance!");
    console.log("This contradicts earlier reports of 2,326.24 WETH.");
    console.log("Possible reasons:");
    console.log("  1. WETH was transferred elsewhere");
    console.log("  2. Wrong wallet address");
    console.log("  3. Wrong WETH contract address");
    console.log("  4. Earlier data was incorrect");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
