const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Create LXON/USDC DEX Pair ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const usdcAddress = process.env.USDC_ADDRESS;
  const factoryAddress = process.env.DEX_FACTORY;

  console.log("LXON Address:", lxonAddress);
  console.log("USDC Address:", usdcAddress);
  console.log("Factory Address:", factoryAddress);

  const factoryABI = [
    "function createPair(address tokenA, address tokenB) external returns (address pair)",
    "function getPair(address tokenA, address tokenB) view returns (address pair)"
  ];

  const factory = new ethers.Contract(factoryAddress, factoryABI, deployer);

  // Check if pair already exists
  const existingPair = await factory.getPair(lxonAddress, usdcAddress);
  console.log("Existing pair:", existingPair);

  if (existingPair !== ethers.ZeroAddress) {
    console.log("✅ Pair already exists:", existingPair);
    console.log("\n=== Update .env ===");
    console.log("Add this line to .env:");
    console.log(`DEX_PAIR_USDC=${existingPair}`);
    return;
  }

  console.log("\nCreating new DEX pair...");
  const tx = await factory.createPair(lxonAddress, usdcAddress);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ New DEX pair created!");

  const pairAddress = await factory.getPair(lxonAddress, usdcAddress);
  console.log("New pair address:", pairAddress);

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`DEX_PAIR_USDC=${pairAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
