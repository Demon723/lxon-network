import { ethers } from "hardhat";

async function main() {
  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const oldDeployerPrivateKey = "e6ba1d2cf3510ad6277c6470814843001702c40b8bdfb3b31c4ece42229a1688";

  console.log("Transferring 1,000 LXON from old deployer to new deployer");

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const provider = await ethers.provider;

  const oldDeployer = new ethers.Wallet(oldDeployerPrivateKey);
  const oldDeployerConnected = oldDeployer.connect(provider);

  // transfer function signature: 0xa9059cbb
  const transferSelector = "0xa9059cbb";
  const amount = ethers.parseUnits("1000", 6);

  const callData = transferSelector + 
    newDeployerAddress.slice(2).padStart(64, '0') + 
    amount.toString(16).padStart(64, '0');

  console.log("\n=== Transfer Details ===");
  console.log("From:", oldDeployerAddress);
  console.log("To:", newDeployerAddress);
  console.log("Amount:", ethers.formatUnits(amount, 6), "LXON");
  console.log("Call data:", callData);

  const tx = await oldDeployerConnected.sendTransaction({
    to: LXON_ADDRESS,
    data: callData
  });

  console.log("\nTransaction sent:", tx.hash);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log("\n✅ Transfer confirmed");
  console.log("Block:", receipt.blockNumber);
  console.log("Gas used:", receipt.gasUsed.toString());

  // Verify new balance
  const balanceOfSelector = "0x70a08231";
  const newCallData = balanceOfSelector + newDeployerAddress.slice(2).padStart(64, '0');
  const newBalance = await provider.call({
    to: LXON_ADDRESS,
    data: newCallData
  });
  console.log("\n=== New Balance ===");
  console.log("New deployer LXON:", ethers.formatUnits(newBalance, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
