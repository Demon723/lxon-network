import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const oldDeployerPrivateKey = "e6ba1d2cf3510ad6277c6470814843001702c40b8bdfb3b31c4ece42229a1688";

  console.log("Transferring LXON from old deployer to new deployer for volume generation");
  console.log("Old deployer:", oldDeployerAddress);
  console.log("New deployer:", newDeployerAddress);

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  const oldDeployer = new ethers.Wallet(oldDeployerPrivateKey);
  const oldDeployerConnected = oldDeployer.connect(await ethers.provider);

  const oldDeployerBalance = await lxon.balanceOf(oldDeployerAddress);
  const newDeployerBalance = await lxon.balanceOf(newDeployerAddress);

  console.log("\n=== Current Balances ===");
  console.log("Old deployer LXON:", ethers.formatUnits(oldDeployerBalance, 6));
  console.log("New deployer LXON:", ethers.formatUnits(newDeployerBalance, 6));

  // Transfer 1,000 LXON for volume generation
  const transferAmount = ethers.parseUnits("1000", 6);
  console.log("\nTransferring 1,000 LXON...");

  const transferTx = await lxon.connect(oldDeployerConnected).transfer(newDeployerAddress, transferAmount);
  await transferTx.wait();
  console.log("Transfer completed");
  console.log("Transaction hash:", transferTx.hash);

  const finalOldBalance = await lxon.balanceOf(oldDeployerAddress);
  const finalNewBalance = await lxon.balanceOf(newDeployerAddress);

  console.log("\n=== Final Balances ===");
  console.log("Old deployer LXON:", ethers.formatUnits(finalOldBalance, 6));
  console.log("New deployer LXON:", ethers.formatUnits(finalNewBalance, 6));

  console.log("\n✅ Ready for volume generation!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
