import { ethers } from "hardhat";
import { Pair } from "../typechain-types";

async function main() {
  const PAIR_ADDRESS = "0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7";
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;

  const [reserve0, reserve1] = await pair.getReserves();
  const totalSupply = await pair.totalSupply();

  console.log("=== Pair Reserves ===");
  console.log("Reserve0 (LXON):", ethers.formatUnits(reserve0, 6));
  console.log("Reserve1 (WETH):", ethers.formatEther(reserve1));
  console.log("Total LP Supply:", ethers.formatEther(totalSupply));
  console.log("Reserves are zero:", reserve0 === 0n && reserve1 === 0n);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
