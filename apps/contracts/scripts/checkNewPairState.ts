import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Checking new Pair state");
  console.log("Account:", deployerAddress);

  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";

  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const newPair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;

  console.log("\n=== Pair Balances ===");
  const pairLXON = await lxon.balanceOf(NEW_PAIR_ADDRESS);
  const pairWETH = await weth.balanceOf(NEW_PAIR_ADDRESS);
  console.log("Pair LXON:", ethers.formatUnits(pairLXON, 6));
  console.log("Pair WETH:", ethers.formatEther(pairWETH));

  console.log("\n=== Pair Reserves ===");
  const [reserve0, reserve1] = await newPair.getReserves();
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));

  console.log("\n=== Deployer Balances ===");
  const deployerLXON = await lxon.balanceOf(deployerAddress);
  const deployerWETH = await weth.balanceOf(deployerAddress);
  console.log("Deployer LXON:", ethers.formatUnits(deployerLXON, 6));
  console.log("Deployer WETH:", ethers.formatEther(deployerWETH));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
