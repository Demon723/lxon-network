import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Verifying LXON balance for volume generation");
  console.log("Account:", newDeployerAddress);

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  const balance = await lxon.balanceOf(newDeployerAddress);

  console.log("\n=== Current Balance ===");
  console.log("LXON balance:", ethers.formatUnits(balance, 6));
  console.log("Required for volume generation: 1,000+ LXON");

  if (Number(ethers.formatUnits(balance, 6)) >= 1000) {
    console.log("\n✅ Sufficient balance for volume generation");
    console.log("Run: npx hardhat run scripts/generateDailyVolume.ts --network lxonDeploy");
  } else {
    console.log("\n❌ Insufficient balance for volume generation");
    console.log("Please transfer 1,000 LXON from old deployer:");
    console.log("Old deployer: 0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5");
    console.log("New deployer: 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27");
    console.log("See: SECURE_LXON_TRANSFER_INSTRUCTIONS.md");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
