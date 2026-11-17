const { ethers } = require("ethers");
require("dotenv").config();

const PAIR_ADDRESS = process.env.DEX_PAIR_2DOLLAR;
const LXON_ADDRESS = process.env.LXON_ADDRESS;
const WETH_ADDRESS = process.env.WETH_MINTABLE;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function token0() view returns (address)",
  "function token1() view returns (address)",
  "event Sync(uint112 reserve0, uint112 reserve1)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
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

  let blockNumber = await provider.getBlockNumber();

  pair.on("Sync", async (reserve0, reserve1) => {
    const currentBlock = await provider.getBlockNumber();
    const reserve0Formatted = ethers.formatUnits(reserve0, decimals0);
    const reserve1Formatted = ethers.formatUnits(reserve1, decimals1);
    const price = Number(reserve0Formatted) / Number(reserve1Formatted);
    const priceUSD = price * 1.5;

    console.log(`\n=== Sync Event - Block ${currentBlock} ===`);
    console.log(`${symbol0} Reserve: ${reserve0Formatted}`);
    console.log(`${symbol1} Reserve: ${reserve1Formatted}`);
    console.log(`Price: ${price.toFixed(6)} ${symbol0}/${symbol1}`);
    console.log(`Price USD: $${priceUSD.toFixed(4)}/LXON`);
  });

  pair.on("Transfer", async (from, to, value) => {
    const currentBlock = await provider.getBlockNumber();
    const valueFormatted = ethers.formatUnits(value, 18);

    console.log(`\n=== Transfer Event - Block ${currentBlock} ===`);
    console.log(`From: ${from}`);
    console.log(`To: ${to}`);
    console.log(`Value: ${valueFormatted} LP Tokens`);
  });

  console.log("Monitoring events...\n");

  // Display current state every 30 seconds
  setInterval(async () => {
    const [reserve0, reserve1] = await pair.getReserves();
    const reserve0Formatted = ethers.formatUnits(reserve0, decimals0);
    const reserve1Formatted = ethers.formatUnits(reserve1, decimals1);
    const price = Number(reserve0Formatted) / Number(reserve1Formatted);
    const priceUSD = price * 1.5;

    console.log(`\n--- Current State ---`);
    console.log(`${symbol0} Reserve: ${reserve0Formatted}`);
    console.log(`${symbol1} Reserve: ${reserve1Formatted}`);
    console.log(`Price: $${priceUSD.toFixed(4)}/LXON`);
  }, 30000);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
