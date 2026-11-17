const { ethers } = require("hardhat");
const dotenv = require("dotenv");
dotenv.config();

async function main() {
  console.log("=== Create New DEX Pair for $2/LXON ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const wethMintableAddress = process.env.WETH_MINTABLE;
  const factoryAddress = process.env.DEX_FACTORY;

  console.log("LXON address:", lxonAddress);
  console.log("WETH Mintable address:", wethMintableAddress);
  console.log("Factory address:", factoryAddress);

  const factoryABI = [
    "function createPair(address tokenA, address tokenB) external returns (address pair)",
    "function getPair(address tokenA, address tokenB) view returns (address pair)"
  ];

  const factory = new ethers.Contract(factoryAddress, factoryABI, deployer);

  // Get existing pair address
  const pairAddress = await factory.getPair(lxonAddress, wethMintableAddress);
  console.log("Pair address:", pairAddress);

  if (pairAddress === ethers.ZeroAddress) {
    console.log("\nCreating new DEX pair...");
    const tx = await factory.createPair(lxonAddress, wethMintableAddress);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ New DEX pair created!");
    const newPairAddress = await factory.getPair(lxonAddress, wethMintableAddress);
    console.log("New pair address:", newPairAddress);
  } else {
    console.log("Pair already exists, using existing pair");
  }

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`DEX_PAIR_2DOLLAR=${pairAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
