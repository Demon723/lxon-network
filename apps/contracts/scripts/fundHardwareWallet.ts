import { ethers } from "hardhat";

async function main() {
  console.log("Funding hardware wallet from old deployer...\n");

  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const hardwareWalletAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Old deployer:", oldDeployerAddress);
  console.log("Hardware wallet:", hardwareWalletAddress);

  // Get old deployer signer
  const oldDeployer = await ethers.getSigner(oldDeployerAddress);

  // Check old deployer balance
  const balance = await oldDeployer.provider.getBalance(oldDeployerAddress);
  console.log("\nOld deployer LXON balance:", ethers.formatEther(balance), "LXON");

  // Amount to transfer (1000 LXON)
  const amountToSend = ethers.parseEther("1000");

  if (balance < amountToSend) {
    console.log("❌ Insufficient balance. Need at least 1000 LXON");
    process.exit(1);
  }

  console.log("\nTransferring 1000 LXON to hardware wallet...");

  const tx = await oldDeployer.sendTransaction({
    to: hardwareWalletAddress,
    value: amountToSend
  });

  console.log("Transaction submitted:", tx.hash);
  await tx.wait();
  console.log("✅ Transfer confirmed");

  // Check new balance
  const newBalance = await oldDeployer.provider.getBalance(hardwareWalletAddress);
  console.log("\nHardware wallet balance:", ethers.formatEther(newBalance), "LXON");

  console.log("\n✅ Hardware wallet funded successfully");
  console.log("Now you can update .env to use hardware wallet as deployer");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
