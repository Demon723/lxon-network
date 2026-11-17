import { ethers } from "hardhat";
import { Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Syncing Pair reserves");
  console.log("Account:", deployerAddress);

  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";
  const newPair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;

  console.log("\nCalling sync()...");
  const syncTx = await newPair.sync();
  await syncTx.wait();
  console.log("Sync completed");
  console.log("Transaction hash:", syncTx.hash);

  // Verify reserves
  const [reserve0, reserve1] = await newPair.getReserves();
  console.log("\n=== Updated Reserves ===");
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
