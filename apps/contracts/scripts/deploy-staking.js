const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy LP Staking Contract ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const lpTokenAddress = process.env.DEX_PAIR_2DOLLAR;
  const rewardTokenAddress = process.env.LXON_ADDRESS;

  console.log("LP Token Address:", lpTokenAddress);
  console.log("Reward Token Address:", rewardTokenAddress);

  const LPStaking = await ethers.getContractFactory("LPStaking");
  const staking = await LPStaking.deploy(lpTokenAddress, rewardTokenAddress);
  await staking.waitForDeployment();

  const stakingAddress = await staking.getAddress();
  console.log("✅ LPStaking deployed to:", stakingAddress);

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`LP_STAKING_ADDRESS=${stakingAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Approve LP tokens for staking");
  console.log("2. Add LXON rewards to staking contract");
  console.log("3. Set reward rate");
  console.log("4. Stake LP tokens");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
