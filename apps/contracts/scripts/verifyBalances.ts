import { ethers } from "hardhat";
import { LXON, WETH9 } from "../typechain-types";

async function main() {
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Verifying balances for volume generation");
  console.log("Account:", newDeployerAddress);

  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  const wethBalance = await weth.balanceOf(newDeployerAddress);
  const lxonBalance = await lxon.balanceOf(newDeployerAddress);

  console.log("\n=== Current Balances ===");
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

  console.log("\n=== Requirements ===");
  console.log("LXON required for selling: 0.1 LXON per swap");
  console.log("WETH required for buyback: 0.00015 WETH per swap");

  if (Number(ethers.formatUnits(lxonBalance, 6)) >= 0.1 && Number(ethers.formatEther(wethBalance)) >= 0.00015) {
    console.log("\n✅ Sufficient balances for two-way swaps");
    console.log("Run: npx hardhat run scripts/generateDailyVolume.ts --network lxonDeploy");
  } else {
    console.log("\n❌ Insufficient balances");
    if (Number(ethers.formatUnits(lxonBalance, 6)) < 0.1) {
      console.log("Need more LXON for selling");
    }
    if (Number(ethers.formatEther(wethBalance)) < 0.00015) {
      console.log("Need more WETH for buyback");
      console.log("Option: Perform a small LXON → WETH swap first to get WETH");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
