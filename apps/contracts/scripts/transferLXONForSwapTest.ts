import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Transferring LXON from old deployer to new deployer for swap testing");
  console.log("Old deployer:", oldDeployerAddress);
  console.log("New deployer:", newDeployerAddress);

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  const oldDeployerBalance = await lxon.balanceOf(oldDeployerAddress);
  const newDeployerBalance = await lxon.balanceOf(newDeployerAddress);

  console.log("\n=== Current Balances ===");
  console.log("Old deployer LXON:", ethers.formatUnits(oldDeployerBalance, 6));
  console.log("New deployer LXON:", ethers.formatUnits(newDeployerBalance, 6));

  // Transfer 1,000 LXON for swap testing
  const transferAmount = ethers.parseUnits("1000", 6);
  console.log("\nTransferring 1,000 LXON...");

  // Since old deployer is not in Hardhat accounts, we need to use a different approach
  // Check if we can use a multi-sig or if the tokens are already accessible
  console.log("Note: Old deployer not in Hardhat accounts");
  console.log("Alternative: Use the 1 LXON available for a small swap test");

  // For now, let's test with a smaller amount that we have
  const availableLXON = Number(ethers.formatUnits(newDeployerBalance, 6));
  console.log("Available LXON for testing:", availableLXON);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
