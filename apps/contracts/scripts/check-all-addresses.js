const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";

// Known addresses to check
const ADDRESSES_TO_CHECK = [
  "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b", // Your wallet
  "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3", // Founder
  "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27", // Deployer
  "0x098Ae030804120Def93880a303788d24dc600d00", // Earlier owner
  "0x3aD52bD5996f16C902225b0d9C111fafE6B77786", // DEX Pair
  "0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602", // Router
  "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06", // New Factory
  "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a", // Universal Router
  "0x4FDa2fC19249F6193b19338639fc161345EB97ff", // Bridge Validator Registry
  "0xfDC175150714C7663D626Dd551f829b1Ba748877", // LXON Bridge
  "0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3", // MultiSig Validator Registry
  "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519", // New DEX Pair
  "0x4d857b3e030bA985c5D32611Ff69238975790Be7", // New WETH
  "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35", // New LXON
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  console.log("=== LXON Token Balance Check Across All Known Addresses ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const lxon = new ethers.Contract(LXON_ADDRESS, ERC20_ABI, provider);
  const weth = new ethers.Contract(WETH_ADDRESS, ERC20_ABI, provider);

  // Get token info
  const lxonDecimals = await lxon.decimals();
  const lxonSymbol = await lxon.symbol();
  const lxonTotalSupply = await lxon.totalSupply();
  const lxonSupplyFormatted = Number(ethers.formatUnits(lxonTotalSupply, lxonDecimals));

  const wethDecimals = await weth.decimals();
  const wethSymbol = await weth.symbol();
  const wethTotalSupply = await weth.totalSupply();
  const wethSupplyFormatted = Number(ethers.formatUnits(wethTotalSupply, wethDecimals));

  console.log("=== Token Overview ===");
  console.log(`${lxonSymbol}:`);
  console.log(`  Total Supply: ${lxonSupplyFormatted.toFixed(4)}`);
  console.log(`  Decimals: ${lxonDecimals}`);
  console.log();
  console.log(`${wethSymbol}:`);
  console.log(`  Total Supply: ${wethSupplyFormatted.toFixed(4)}`);
  console.log(`  Decimals: ${wethDecimals}`);
  console.log();

  // Check all addresses
  console.log("=== LXON Balances by Address ===");
  let totalLxon = 0n;
  let nonZeroCount = 0;

  for (const address of ADDRESSES_TO_CHECK) {
    const balance = await lxon.balanceOf(address);
    const formatted = Number(ethers.formatUnits(balance, lxonDecimals));
    totalLxon += balance;

    if (balance > 0n) {
      nonZeroCount++;
      console.log(`✅ ${address}`);
      console.log(`   Balance: ${formatted.toFixed(4)} ${lxonSymbol}`);
    }
  }

  if (nonZeroCount === 0) {
    console.log("❌ No LXON found in any known address");
  }

  console.log();
  console.log(`Total LXON in known addresses: ${Number(ethers.formatUnits(totalLxon, lxonDecimals)).toFixed(4)}`);
  console.log(`Addresses with non-zero balance: ${nonZeroCount}/${ADDRESSES_TO_CHECK.length}`);
  console.log();

  // Check WETH balances
  console.log("=== WETH Balances by Address ===");
  let totalWeth = 0n;
  let wethNonZeroCount = 0;

  for (const address of ADDRESSES_TO_CHECK) {
    const balance = await weth.balanceOf(address);
    const formatted = Number(ethers.formatUnits(balance, wethDecimals));
    totalWeth += balance;

    if (balance > 0n) {
      wethNonZeroCount++;
      console.log(`✅ ${address}`);
      console.log(`   Balance: ${formatted.toFixed(4)} ${wethSymbol}`);
    }
  }

  if (wethNonZeroCount === 0) {
    console.log("❌ No WETH found in any known address");
  }

  console.log();
  console.log(`Total WETH in known addresses: ${Number(ethers.formatUnits(totalWeth, wethDecimals)).toFixed(4)}`);
  console.log(`Addresses with non-zero balance: ${wethNonZeroCount}/${ADDRESSES_TO_CHECK.length}`);
  console.log();

  // Summary
  console.log("=== Summary ===");
  console.log(`${lxonSymbol} Total Supply: ${lxonSupplyFormatted.toFixed(4)}`);
  console.log(`${lxonSymbol} in known addresses: ${Number(ethers.formatUnits(totalLxon, lxonDecimals)).toFixed(4)}`);
  console.log(`${lxonSymbol} unaccounted: ${(lxonSupplyFormatted - Number(ethers.formatUnits(totalLxon, lxonDecimals))).toFixed(4)}`);
  console.log();
  console.log(`${wethSymbol} Total Supply: ${wethSupplyFormatted.toFixed(4)}`);
  console.log(`${wethSymbol} in known addresses: ${Number(ethers.formatUnits(totalWeth, wethDecimals)).toFixed(4)}`);
  console.log(`${wethSymbol} unaccounted: ${(wethSupplyFormatted - Number(ethers.formatUnits(totalWeth, wethDecimals))).toFixed(4)}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
