const { ethers } = require("hardhat");
const dotenv = require("dotenv");
dotenv.config();

async function main() {
  console.log("=== Deploy New WETH Contract ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const WETH9Mintable = await ethers.getContractFactory("WETH9Mintable");
  const weth = await WETH9Mintable.deploy();
  await weth.waitForDeployment();

  const wethAddress = await weth.getAddress();
  console.log("✅ WETH9Mintable deployed to:", wethAddress);

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`NEW_WETH_ADDRESS=${wethAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Mint 111.6M WETH");
  console.log("2. Create new DEX pair");
  console.log("3. Add liquidity to achieve $2/LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
