const { ethers } = require("ethers");
require("dotenv").config();

const PAIR_ADDRESS = process.env.DEX_PAIR_2DOLLAR;
const LXON_ADDRESS = process.env.LXON_ADDRESS;
const WETH_ADDRESS = process.env.WETH_MINTABLE;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

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
  console.log("=== Monitor DEX Trading Activity ===\n");
  console.log("Pair Address:", PAIR_ADDRESS);
  console.log("Press Ctrl+C to stop monitoring\n");

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, provider);

  const token0 = await pair.token0();
  const token1 = await pair.token1();

  const token0Contract = new ethers.Contract(token0, ERC20_ABI, provider);
  const token1Contract = new ethers.Contract(token1, ERC20_ABI, provider);

  const symbol0 = await token0Contract.symbol();
  const symbol1 = await token1Contract.symbol();
  const decimals0 = await token0Contract.decimals();
  const decimals1 = await token1Contract.decimals();

  console.log(`Token0 (${symbol0}):`, token0);
  console.log(`Token1 (${symbol1}):`, token1);
  console.log("");

  let previousReserve0 = 0n;
  let previousReserve1 = 0n;

  while (true) {
    const [reserve0, reserve1] = await pair.getReserves();
    const reserve0Formatted = ethers.formatUnits(reserve0, decimals0);
    const reserve1Formatted = ethers.formatUnits(reserve1, decimals1);
    const price = Number(reserve0Formatted) / Number(reserve1Formatted);
    const priceUSD = price * 1.5;

    const currentBlock = await provider.getBlockNumber();
    const timestamp = new Date().toLocaleTimeString();

    console.log(`\n[${timestamp}] Block ${currentBlock}`);
    console.log(`${symbol0} Reserve: ${reserve0Formatted}`);
    console.log(`${symbol1} Reserve: ${reserve1Formatted}`);
    console.log(`Price: $${priceUSD.toFixed(4)}/LXON`);

    if (reserve0 !== previousReserve0 || reserve1 !== previousReserve1) {
      console.log("⚠️  RESERVES CHANGED - Trading Activity Detected!");
      const reserve0Change = Number(reserve0Formatted) - Number(ethers.formatUnits(previousReserve0, decimals0));
      const reserve1Change = Number(reserve1Formatted) - Number(ethers.formatUnits(previousReserve1, decimals1));
      console.log(`${symbol0} Change: ${reserve0Change.toFixed(6)}`);
      console.log(`${symbol1} Change: ${reserve1Change.toFixed(6)}`);
    }

    previousReserve0 = reserve0;
    previousReserve1 = reserve1;

    await new Promise(resolve => setTimeout(resolve, 10000)); // Check every 10 seconds
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
