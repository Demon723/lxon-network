import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deploying fixed Router contract");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  console.log("\n=== Deploying Router ===");
  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy(WETH_ADDRESS, LXON_ADDRESS, PAIR_ADDRESS) as Router;
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();

  console.log("Router deployed to:", routerAddress);
  console.log("Transaction hash:", router.deploymentTransaction()?.hash);

  console.log("\n=== Contract Addresses ===");
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);
  console.log("Pair:", PAIR_ADDRESS);
  console.log("New Router:", routerAddress);
  console.log("Old Router: 0x0De021F0caA907e11f06a2bd78767b1a3557D8A3");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
