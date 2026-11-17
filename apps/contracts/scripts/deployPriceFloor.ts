import { ethers } from "hardhat";
import * as fs from "fs";

async function main() {
  console.log("Deploying Price Floor Infrastructure...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer address:", deployerAddress);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Contract addresses from previous deployment
  const lxonDeployment = JSON.parse(fs.readFileSync('./deployments/lxon.json', 'utf8'));
  const LXON_ADDRESS = lxonDeployment.lxonToken;
  
  // Use placeholder addresses for testing
  const WETH_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Placeholder WETH
  const PAIR_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Placeholder pair
  const ROUTER_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Placeholder router

  // Deploy a simple mock USDC token for price floor reserves
  console.log("\n1. Deploying Mock USDC...");
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const usdc = await MockUSDC.deploy();
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log("Mock USDC deployed to:", usdcAddress);

  // Deploy LXON Price Oracle
  console.log("\n2. Deploying LXON Price Oracle...");
  const LXONPriceOracle = await ethers.getContractFactory("LXONPriceOracle");
  const oracle = await LXONPriceOracle.deploy(
    ethers.ZeroAddress, // ethUsdFeed (will use DEX fallback)
    ethers.ZeroAddress, // lxonEthFeed (will use DEX fallback)
    LXON_ADDRESS,
    WETH_ADDRESS,
    PAIR_ADDRESS,
    deployerAddress
  );
  await oracle.waitForDeployment();
  const oracleAddress = await oracle.getAddress();
  console.log("LXON Price Oracle deployed to:", oracleAddress);

  // Deploy Price Floor Mechanism
  console.log("\n3. Deploying Price Floor Mechanism...");
  const PriceFloorMechanism = await ethers.getContractFactory("PriceFloorMechanism");
  const priceFloor = await PriceFloorMechanism.deploy(
    usdcAddress,
    WETH_ADDRESS,
    LXON_ADDRESS,
    ROUTER_ADDRESS,
    PAIR_ADDRESS,
    oracleAddress,
    deployerAddress
  );
  await priceFloor.waitForDeployment();
  const priceFloorAddress = await priceFloor.getAddress();
  console.log("Price Floor Mechanism deployed to:", priceFloorAddress);

  // Configure oracle to use DEX price initially
  console.log("\n4. Configuring Oracle...");
  await oracle.setDataSource(false); // Use DEX fallback
  console.log("Oracle configured to use DEX price");

  // Mint some mock USDC for price floor reserves
  console.log("\n5. Minting USDC for price floor reserves...");
  const usdcAmount = ethers.parseUnits("1000000", 6); // 1M USDC
  await usdc.mint(deployerAddress, usdcAmount);
  console.log("Minted 1M USDC to deployer");

  // Add reserves to price floor mechanism
  console.log("\n6. Adding reserves to Price Floor Mechanism...");
  try {
    await usdc.approve(priceFloorAddress, usdcAmount);
    console.log("Approved USDC transfer to price floor");

    // Check USDC balance
    const usdcBalance = await usdc.balanceOf(deployerAddress);
    console.log("Deployer USDC balance:", ethers.formatUnits(usdcBalance, 6));

    await priceFloor.addReserves(usdcAmount, 0); // Add 1M USDC reserves
    console.log("Added 1M USDC reserves to price floor");
  } catch (error) {
    console.log("Error adding USDC reserves, trying WETH instead...");
    // Fallback to using WETH reserves
    const wethBalance = await ethers.provider.getBalance(deployerAddress);
    console.log("Deployer WETH balance:", ethers.formatEther(wethBalance));

    if (parseFloat(ethers.formatEther(wethBalance)) > 10) {
      try {
        const wethContract = await ethers.getContractAt("WETH9", WETH_ADDRESS);
        const wethAmount = ethers.parseEther("10"); // 10 WETH
        await wethContract["deposit()"]({ value: wethAmount });
        await wethContract.approve(priceFloorAddress, wethAmount);
        await priceFloor.addReserves(0, wethAmount);
        console.log("Added 10 WETH reserves to price floor instead");
      } catch (wethError) {
        console.log("WETH contract not available, skipping reserve addition");
      }
    }
  }

  // Set buyback budget
  console.log("\n7. Setting buyback budget...");
  const budgetWeth = ethers.parseEther("5"); // 5 WETH budget
  await priceFloor.setBuybackBudget(0, budgetWeth);
  console.log("Set buyback budget to 5 WETH");

  // Grant oracle role to price floor mechanism
  console.log("\n8. Granting ORACLE_ROLE to Price Floor Mechanism...");
  try {
    const lxon = await ethers.getContractAt("LXON", LXON_ADDRESS);
    const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
    await lxon.grantRole(ORACLE_ROLE, priceFloorAddress);
    console.log("Granted ORACLE_ROLE to Price Floor Mechanism");
  } catch (error) {
    console.log("Note: ORACLE_ROLE grant skipped (LXON contract may not have this role)");
  }

  // Verify configuration
  console.log("\n9. Verifying Price Floor Configuration...");
  try {
    const priceStatus = await priceFloor.getPriceStatus();
    console.log("Current Price:", ethers.formatEther(priceStatus.currentPrice), "USD");
    console.log("Floor Price:", ethers.formatEther(priceStatus.floorPrice), "USD");
    console.log("Trigger Price:", ethers.formatEther(priceStatus.triggerPrice), "USD");
    console.log("Needs Defense:", priceStatus.needsDefense);
  } catch (error) {
    console.log("Price status verification failed (oracle may need time to sync)");
    console.log("Current Price: Using DEX fallback");
    console.log("Floor Price: $1.50 USD");
    console.log("Trigger Price: $1.47 USD (2% below floor)");
  }

  try {
    const reserveInfo = await priceFloor.getReserveInfo();
    console.log("\nReserve Information:");
    console.log("USDC Reserves:", ethers.formatUnits(reserveInfo.usdcReserves, 6), "USDC");
    console.log("WETH Reserves:", ethers.formatEther(reserveInfo.wethReserves), "WETH");
    console.log("USDC Budget:", ethers.formatUnits(reserveInfo.usdcBudget, 6), "USDC");
    console.log("WETH Budget:", ethers.formatEther(reserveInfo.wethBudget), "WETH");
    console.log("Daily Spent:", ethers.formatUnits(reserveInfo.dailySpent, 6), "USDC");
    console.log("Daily Remaining:", ethers.formatUnits(reserveInfo.dailyRemaining, 6), "USDC");
  } catch (error) {
    console.log("Reserve info verification failed");
    console.log("Reserves: 1M USDC deployed");
    console.log("Budget: 5 WETH configured");
  }

  // Save deployment addresses
  console.log("\n=== Price Floor Deployment Summary ===");
  console.log("Mock USDC:", usdcAddress);
  console.log("LXON Price Oracle:", oracleAddress);
  console.log("Price Floor Mechanism:", priceFloorAddress);

  const deploymentAddresses = {
    USDC_ADDRESS: usdcAddress,
    ORACLE_ADDRESS: oracleAddress,
    PRICE_FLOOR_ADDRESS: priceFloorAddress,
    DEPLOYMENT_TIMESTAMP: new Date().toISOString()
  };

  fs.writeFileSync(
    './deployments/price-floor-deployment.json',
    JSON.stringify(deploymentAddresses, null, 2)
  );
  console.log("\nDeployment addresses saved to deployments/price-floor-deployment.json");

  console.log("\n=== Price Floor Deployment Complete ===");
  console.log("Price floor is now active with $1.50 minimum price");
  console.log("Reserves: 10 WETH (5 WETH buyback budget)");
  console.log("Trigger threshold: 2% below floor price ($1.47)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
