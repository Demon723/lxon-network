import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  console.log("Deploying fresh LXON DEX contracts...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const deployer = await ethers.getSigner(deployerAddress);

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
  
  // Set reserve ceiling high enough for 100M tokens
  // reserveCeiling * 1e4 must be >= totalSupply
  // For 100M tokens: reserveCeiling >= 100M / 1e4 = 10,000
  // Set to 20,000 to be safe
  await lxon.updateCeiling(20000, ethers.ZeroHash);
  console.log("LXON roles configured with reserve ceiling: 20,000");

  // Deploy Pair
  console.log("\n4. Deploying Pair...");
  const Pair = await ethers.getContractFactory("Pair");
  const pair = await Pair.deploy(wethAddress, lxonAddress);
  await pair.waitForDeployment();
  const pairAddress = await pair.getAddress();
  console.log("Pair deployed to:", pairAddress);

  // Verify pair initialization
  const token0 = await pair.token0();
  const token1 = await pair.token1();
  console.log("Pair token0:", token0, "(WETH)");
  console.log("Pair token1:", token1, "(LXON)");

  // Deploy Router
  console.log("\n5. Deploying Router...");
  const Router = await ethers.getContractFactory("Router");
  const router = await Router.deploy(wethAddress, lxonAddress, pairAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log("Router deployed to:", routerAddress);

  // Mint initial LXON supply
  console.log("\n6. Minting initial LXON supply...");
  // LXON mint takes usdCents, which gets multiplied by 1e4 for token amount
  // To get 100M tokens: usdCents * 1e4 = 100M, so usdCents = 100M / 1e4 = 10,000
  // 10,000 cents = $100 USD worth of tokens
  const usdCentsFor100M = 10000n; // 10,000 cents = $100
  await lxon.mint(deployerAddress, usdCentsFor100M, ethers.ZeroHash);
  console.log("Minted 100M LXON to deployer");

  const lxonBalance = await lxon.balanceOf(deployerAddress);
  console.log("Deployer LXON balance:", ethers.formatEther(lxonBalance));

  // Log deployment summary
  console.log("\n=== Deployment Summary ===");
  console.log("WETH9:", wethAddress);
  console.log("LXON:", lxonAddress);
  console.log("Pair:", pairAddress);
  console.log("Router:", routerAddress);
  console.log("Deployer:", deployerAddress);

  // Save addresses to file for easy reference
  const deploymentAddresses = {
    WETH_ADDRESS: wethAddress,
    LXON_ADDRESS: lxonAddress,
    PAIR_ADDRESS: pairAddress,
    ROUTER_ADDRESS: routerAddress,
    DEPLOYER: deployerAddress,
    DEPLOYMENT_TIMESTAMP: new Date().toISOString()
  };

  const fs = require('fs');
  fs.writeFileSync(
    './deployments/fresh-contracts.json',
    JSON.stringify(deploymentAddresses, null, 2)
  );
  console.log("\nDeployment addresses saved to deployments/fresh-contracts.json");

  console.log("\n=== Next Steps ===");
  console.log("1. Update .env file with the new addresses");
  console.log("2. Run: npm run deploy:liquidity");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });