import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  console.log("=== Pair Token Balances ===");
  const pairLXONBalance = await lxon.balanceOf(PAIR_ADDRESS);
  const pairWETHBalance = await weth.balanceOf(PAIR_ADDRESS);
  
  console.log("Pair LXON balance:", ethers.formatUnits(pairLXONBalance, 6));
  console.log("Pair WETH balance:", ethers.formatEther(pairWETHBalance));

  console.log("\n=== Pair Reserves ===");
  const [reserve0, reserve1] = await pair.getReserves();
  console.log("Reserve0 (LXON):", ethers.formatUnits(reserve0, 6));
  console.log("Reserve1 (WETH):", ethers.formatEther(reserve1));

  console.log("\n=== Difference ===");
  console.log("LXON difference:", ethers.formatUnits(pairLXONBalance - reserve0, 6));
  console.log("WETH difference:", ethers.formatEther(pairWETHBalance - reserve1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
