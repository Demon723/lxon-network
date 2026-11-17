import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const oldDeployer = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployer = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const oldDeployerSigner = await ethers.getSigner(oldDeployer);

  console.log("Transferring LXON from old deployer to new deployer");
  console.log("From:", oldDeployer);
  console.log("To:", newDeployer);

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  const oldBalance = await lxon.balanceOf(oldDeployer);
  console.log("Old deployer LXON balance:", ethers.formatUnits(oldBalance, 6));

  const transferAmount = ethers.parseUnits("1000", 6);
  
  if (oldBalance < transferAmount) {
    console.log("Insufficient balance to transfer");
    return;
  }

  console.log("Transferring 1000 LXON...");
  const tx = await lxon.connect(oldDeployerSigner).transfer(newDeployer, transferAmount);
  await tx.wait();
  console.log("Transfer successful!");
  console.log("Transaction hash:", tx.hash);

  const newBalance = await lxon.balanceOf(newDeployer);
  console.log("New deployer LXON balance:", ethers.formatUnits(newBalance, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
