import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Diagnosing Pair token order and reserves");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;

  console.log("\n=== Token Addresses ===");
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);
  console.log("Pair:", PAIR_ADDRESS);

  console.log("\n=== Pair Token Order ===");
  const token0 = await pair.token0();
  const token1 = await pair.token1();
  console.log("Pair.token0:", token0);
  console.log("Pair.token1:", token1);
  console.log("Is token0 WETH?", token0.toLowerCase() === WETH_ADDRESS.toLowerCase());
  console.log("Is token0 LXON?", token0.toLowerCase() === LXON_ADDRESS.toLowerCase());
  console.log("Is token1 WETH?", token1.toLowerCase() === WETH_ADDRESS.toLowerCase());
  console.log("Is token1 LXON?", token1.toLowerCase() === LXON_ADDRESS.toLowerCase());

  console.log("\n=== Actual Token Balances in Pair ===");
  const wethBalance = await weth.balanceOf(PAIR_ADDRESS);
  const lxonBalance = await lxon.balanceOf(PAIR_ADDRESS);
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

  console.log("\n=== Pair Reserves ===");
  const [reserve0, reserve1] = await pair.getReserves();
  console.log("Reserve0 (raw):", reserve0.toString());
  console.log("Reserve1 (raw):", reserve1.toString());

  // Try to interpret reserves based on token order
  if (token0.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
    console.log("\n=== Token Order: token0=WETH, token1=LXON ===");
    console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
    console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));
  } else if (token0.toLowerCase() === LXON_ADDRESS.toLowerCase()) {
    console.log("\n=== Token Order: token0=LXON, token1=WETH ===");
    console.log("Reserve0 (LXON):", ethers.formatUnits(reserve0, 6));
    console.log("Reserve1 (WETH):", ethers.formatEther(reserve1));
  }

  console.log("\n=== Calling forceSync to fix reserves ===");
  const syncTx = await pair.forceSync();
  await syncTx.wait();
  console.log("forceSync completed");

  console.log("\n=== Reserves After forceSync ===");
  const [reserve0After, reserve1After] = await pair.getReserves();
  console.log("Reserve0 (raw):", reserve0After.toString());
  console.log("Reserve1 (raw):", reserve1After.toString());

  if (token0.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
    console.log("Reserve0 (WETH):", ethers.formatEther(reserve0After));
    console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1After, 6));
  } else if (token0.toLowerCase() === LXON_ADDRESS.toLowerCase()) {
    console.log("Reserve0 (LXON):", ethers.formatUnits(reserve0After, 6));
    console.log("Reserve1 (WETH):", ethers.formatEther(reserve1After));
  }

  // Calculate price
  let pricePerLXON = 0;
  if (token0.toLowerCase() === LXON_ADDRESS.toLowerCase()) {
    pricePerLXON = Number(reserve1After) / Number(reserve0After);
  } else if (token1.toLowerCase() === LXON_ADDRESS.toLowerCase()) {
    pricePerLXON = Number(reserve0After) / Number(reserve1After);
  }

  const ETH_PRICE_USD = 3000;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;

  console.log("\n=== Price Calculation ===");
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD);
  console.log("Target price: $1.50");
  console.log("Price deviation:", ((priceUSD - 1.5) / 1.5 * 100).toFixed(2), "%");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
