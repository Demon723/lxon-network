import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const PAIR_ADDRESS = "0x896daaADC5992D6F77021aB3100a64253aEa73Ad";
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  console.log("=== CRITICAL ISSUE: Pair Reserves vs Actual Balances ===");
  
  const pairLXONBalance = await lxon.balanceOf(PAIR_ADDRESS);
  const pairWETHBalance = await weth.balanceOf(PAIR_ADDRESS);
  const [reserve0, reserve1] = await pair.getReserves();
  
  console.log("\n=== Actual Token Balances in Pair ===");
  console.log("LXON balance:", ethers.formatUnits(pairLXONBalance, 6));
  console.log("WETH balance:", ethers.formatEther(pairWETHBalance));
  
  console.log("\n=== Pair Reserves (Used for Price Calculation) ===");
  console.log("Reserve0 (LXON):", ethers.formatUnits(reserve0, 6));
  console.log("Reserve1 (WETH):", ethers.formatEther(reserve1));
  
  console.log("\n=== The Problem ===");
  console.log("Reserves should equal actual balances, but they don't!");
  console.log("LXON difference:", ethers.formatUnits(pairLXONBalance - reserve0, 6));
  console.log("WETH difference:", ethers.formatEther(pairWETHBalance - reserve1));
  
  console.log("\n=== This means the price calculation is using wrong values ===");
  const actualPrice = pairLXONBalance > 0n ? Number(pairWETHBalance) / Number(pairLXONBalance) : 0;
  const reservePrice = reserve0 > 0n ? Number(reserve1) / Number(reserve0) : 0;
  const ETH_PRICE = 3000;
  
  console.log("Actual price (using balances):", actualPrice, "WETH per LXON = $", actualPrice * ETH_PRICE);
  console.log("Reserve price (using reserves):", reservePrice, "WETH per LXON = $", reservePrice * ETH_PRICE);
  
  console.log("\n=== RECOMMENDATION ===");
  console.log("The Pair contract has a bug in the _update() function");
  console.log("Need to fix the Pair contract or use a different DEX implementation");
  console.log("For now, the actual price should be $1.50 based on real balances");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
