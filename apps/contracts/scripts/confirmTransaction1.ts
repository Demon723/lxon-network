import { ethers } from "hardhat";

async function main() {
  console.log("Confirming transaction 1 with deployer...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const deployer = await ethers.getSigner(deployerAddress);

  const multiSigAddress = "0x9EE0Ca5C1edFc13a9540E89d1F055D0FC87def02";

  const multiSigAbi = [
    "function confirmTransaction(uint256 transactionId) external",
    "function getConfirmationCount(uint256 transactionId) external view returns (uint256)",
    "function isConfirmed(uint256 transactionId) external view returns (bool)",
    "function threshold() external view returns (uint256)"
  ];

  const multiSig = new ethers.Contract(multiSigAddress, multiSigAbi, deployer);

  console.log("Confirming transaction 1 (revoke ORACLE_ROLE)...");

  const tx = await multiSig.confirmTransaction(1);
  console.log("Transaction submitted:", tx.hash);
  await tx.wait();
  console.log("✅ Transaction 1 confirmed");

  // Check status
  const threshold = await multiSig.threshold();
  const confirmationCount0 = await multiSig.getConfirmationCount(0);
  const confirmationCount1 = await multiSig.getConfirmationCount(1);
  const isConfirmed0 = await multiSig.isConfirmed(0);
  const isConfirmed1 = await multiSig.isConfirmed(1);

  console.log("\n=== Current Status ===");
  console.log("Threshold:", threshold.toString());
  console.log("Transaction 0:", confirmationCount0.toString(), "/", threshold.toString(), "confirmations, confirmed:", isConfirmed0);
  console.log("Transaction 1:", confirmationCount1.toString(), "/", threshold.toString(), "confirmations, confirmed:", isConfirmed1);

  console.log("\n⚠️  Both transactions still need your MetaMask signature to reach 2/2");
  console.log("Transaction 0 needs 1 more confirmation");
  console.log("Transaction 1 needs 1 more confirmation");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
