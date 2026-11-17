const { ethers } = require("ethers");
require("dotenv").config();

// Original DEX pair address
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function token0() view returns (address)",
  "function token1() view returns (address)"
];

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  console.log("=== Current LXON Price Check ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);
  const weth = new ethers.Contract(WETH_ADDRESS, ERC20_ABI, provider);
  const lxon = new ethers.Contract(LXON_ADDRESS, ERC20_ABI, provider);

  // Get token info
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();
  const wethSymbol = await weth.symbol();
  const lxonSymbol = await lxon.symbol();

  console.log("Token Info:");
  console.log(`${wethSymbol}: ${wethDecimals} decimals`);
  console.log(`${lxonSymbol}: ${lxonDecimals} decimals\n`);

  // Get reserves
  const [reserve0, reserve1] = await pair.getReserves();
  const token0 = await pair.token0();
  const token1 = await pair.token1();

  console.log("Pair Reserves:");
  console.log(`Token0: ${token0}`);
  console.log(`Token1: ${token1}\n`);

  // Determine which is which
  let wethReserve, lxonReserve;
  if (token0.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
    wethReserve = reserve0;
    lxonReserve = reserve1;
  } else {
    wethReserve = reserve1;
    lxonReserve = reserve0;
  }

  const wethBalance = Number(ethers.formatUnits(wethReserve, wethDecimals));
  const lxonBalance = Number(ethers.formatUnits(lxonReserve, lxonDecimals));

  console.log("Balances in Pair:");
  console.log(`${wethSymbol}: ${wethBalance.toFixed(4)}`);
  console.log(`${lxonSymbol}: ${lxonBalance.toFixed(4)}\n`);

  // Calculate price
  if (lxonBalance > 0) {
    const wethPerLxon = wethBalance / lxonBalance;
    console.log("Current Price:");
    console.log(`1 ${lxonSymbol} = ${wethPerLxon.toFixed(6)} ${wethSymbol}`);
    console.log(`1 ${wethSymbol} = ${(1 / wethPerLxon).toFixed(2)} ${lxonSymbol}\n`);

    // Assuming ETH price of $3,000 (you may want to update this)
    const ethPrice = 3000;
    const lxonPriceUsd = wethPerLxon * ethPrice;
    console.log(`Estimated USD Price (assuming ETH = $${ethPrice}):`);
    console.log(`1 ${lxonSymbol} = $${lxonPriceUsd.toFixed(4)} USD`);
    console.log(`1 USD = ${(1 / lxonPriceUsd).toFixed(2)} ${lxonSymbol}\n`);

    // Total value
    const totalWeth = wethBalance;
    const totalUsd = totalWeth * ethPrice;
    console.log("Total Liquidity:");
    console.log(`${wethSymbol}: ${totalWeth.toFixed(4)} (~$${totalUsd.toFixed(2)} USD)`);
  } else {
    console.log("No LXON liquidity in pair");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
