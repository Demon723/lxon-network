const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy Yield Farm Contract ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const stakingTokenAddress = process.env.DEX_PAIR_2DOLLAR;
  const rewardTokenAddress = process.env.LXON_ADDRESS;

  console.log("Staking Token (LP):", stakingTokenAddress);
  console.log("Reward Token (LXON):", rewardTokenAddress);

  const currentBlock = await ethers.provider.getBlockNumber();
  const startBlock = currentBlock + 10;
  const endBlock = startBlock + 1000000; // ~1 million blocks

  const rewardPerBlock = ethers.parseEther("100"); // 100 LXON per block

  console.log("Start Block:", startBlock);
  console.log("End Block:", endBlock);
  console.log("Reward Per Block:", ethers.formatEther(rewardPerBlock), "LXON");

  const YieldFarm = await ethers.getContractFactory("YieldFarm");
  const yieldFarm = await YieldFarm.deploy(
    stakingTokenAddress,
    rewardTokenAddress,
    rewardPerBlock,
    startBlock,
    endBlock
  );
  await yieldFarm.waitForDeployment();

  const yieldFarmAddress = await yieldFarm.getAddress();
  console.log("✅ YieldFarm deployed to:", yieldFarmAddress);

  // Add pool
  const allocPoint = 1000;
  const tx = await yieldFarm.addPool(allocPoint);
  await tx.wait();
  console.log("✅ Pool added with allocPoint:", allocPoint);

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`YIELD_FARM_ADDRESS=${yieldFarmAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Add LXON rewards to yield farm");
  console.log("2. Stake LP tokens to earn rewards");
  console.log("3. Claim rewards periodically");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
