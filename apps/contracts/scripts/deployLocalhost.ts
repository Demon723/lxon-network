import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  console.log("Deploying LXON DEX contracts on localhost for testing...");
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  
  console.log("Deployer address:", deployerAddress);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Deploy WETH9
  console.log("\n1. Deploying WETH9...");
  const WETH9 = await ethers.getContractFactory("WETH9");
  const weth = await WETH9.deploy();
  await weth.waitForDeployment();
  const wethAddress = await weth.getAddress();
  console.log("WETH9 deployed to:", wethAddress);

  // Deploy LXON
  console.log("\n2. Deploying LXON...");
  const LXON = await ethers.getContractFactory("LXON");
  const lxon = await LXON.deploy(deployerAddress);
  await lxon.waitForDeployment();
  const lxonAddress = await lxon.getAddress();
  console.log("LXON deployed to:", lxonAddress);

  // Setup LXON roles
  console.log("\n3. Setting up LXON roles...");
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  
  await lxon.grantRole(MINT_ROLE, deployerAddress);
  await lxon.grantRole(ORACLE_ROLE, deployerAddress);
  await lxon.updateCeiling(20000, ethers.ZeroHash);
  console.log("LXON roles configured");

  // Mint initial LXON supply
  console.log("\n4. Minting initial LXON supply...");
  const usdCentsFor100M = 10000n; // 10,000 cents = $100
  await lxon.mint(deployerAddress, usdCentsFor100M, ethers.ZeroHash);
  console.log("Minted 100M LXON to deployer");

  const lxonBalance = await lxon.balanceOf(deployerAddress);
  console.log("Deployer LXON balance:", ethers.formatEther(lxonBalance));

  // Deploy Pair
  console.log("\n5. Deploying Pair...");
  const Pair = await ethers.getContractFactory("Pair");
  const pair = await Pair.deploy(wethAddress, lxonAddress);
  await pair.waitForDeployment();
  const pairAddress = await pair.getAddress();
  console.log("Pair deployed to:", pairAddress);

  // Deploy Router
  console.log("\n6. Deploying Router...");
  const Router = await ethers.getContractFactory("Router");
  const router = await Router.deploy(wethAddress, lxonAddress, pairAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log("Router deployed to:", routerAddress);

  // Save addresses to file
  const deploymentAddresses = {
    WETH_ADDRESS: wethAddress,
    LXON_ADDRESS: lxonAddress,
    PAIR_ADDRESS: pairAddress,
    ROUTER_ADDRESS: routerAddress,
    DEPLOYER: deployerAddress,
    DEPLOYMENT_TIMESTAMP: new Date().toISOString(),
    NETWORK: "localhost"
  };

  const fs = require('fs');
  fs.writeFileSync(
    './deployments/localhost-contracts.json',
    JSON.stringify(deploymentAddresses, null, 2)
  );
  console.log("\nDeployment addresses saved to deployments/localhost-contracts.json");

  console.log("\n=== Deployment Summary ===");
  console.log("WETH9:", wethAddress);
  console.log("LXON:", lxonAddress);
  console.log("Pair:", pairAddress);
  console.log("Router:", routerAddress);
  console.log("Network: localhost (Hardhat)");

  console.log("\n=== Next Steps ===");
  console.log("1. Test liquidity addition locally");
  console.log("2. Verify all functionality works");
  console.log("3. Plan deployment to LXON mainnet when method available");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });