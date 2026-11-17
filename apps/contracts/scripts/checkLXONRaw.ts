import { ethers } from "hardhat";

async function main() {
  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Checking LXON balances using raw call");

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const provider = await ethers.provider;

  // balanceOf function signature: 0x70a08231
  const balanceOfSelector = "0x70a08231";

  console.log("\n=== Raw Balance Calls ===");

  // Old deployer balance
  const oldCallData = balanceOfSelector + oldDeployerAddress.slice(2).padStart(64, '0');
  const oldBalance = await provider.call({
    to: LXON_ADDRESS,
    data: oldCallData
  });
  console.log("Old deployer raw balance:", oldBalance);
  console.log("Old deployer LXON:", ethers.formatUnits(oldBalance, 6));

  // New deployer balance
  const newCallData = balanceOfSelector + newDeployerAddress.slice(2).padStart(64, '0');
  const newBalance = await provider.call({
    to: LXON_ADDRESS,
    data: newCallData
  });
  console.log("New deployer raw balance:", newBalance);
  console.log("New deployer LXON:", ethers.formatUnits(newBalance, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
