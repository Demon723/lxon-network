import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Checking LXON token contract status");

  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  console.log("\n=== Token Info ===");
  console.log("Address:", LXON_ADDRESS);
  console.log("Name:", await lxon.name());
  console.log("Symbol:", await lxon.symbol());
  console.log("Decimals:", await lxon.decimals());
  console.log("Total Supply:", ethers.formatUnits(await lxon.totalSupply(), 6));

  console.log("\n=== Balances ===");
  const oldBalance = await lxon.balanceOf(oldDeployerAddress);
  const newBalance = await lxon.balanceOf(newDeployerAddress);
  console.log("Old deployer:", ethers.formatUnits(oldBalance, 6), "LXON");
  console.log("New deployer:", ethers.formatUnits(newBalance, 6), "LXON");

  console.log("\n=== Contract Status ===");
  try {
    const paused = await lxon.paused();
    console.log("Paused:", paused);
  } catch (e) {
    console.log("Paused check failed");
  }

  console.log("\n=== Recent Transfer Events ===");
  const filter = lxon.filters.Transfer(oldDeployerAddress, newDeployerAddress);
  const events = await lxon.queryFilter(filter, -100);
  console.log("Transfer events found:", events.length);
  events.forEach((event, index) => {
    console.log(`Event ${index + 1}:`);
    console.log("  Block:", event.blockNumber);
    console.log("  TX:", event.transactionHash);
    console.log("  Amount:", ethers.formatUnits(event.args[2], 6), "LXON");
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
