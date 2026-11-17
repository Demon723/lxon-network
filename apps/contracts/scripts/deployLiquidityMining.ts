import { ethers } from "hardhat";

/**
 * Deploy LXON Liquidity Mining Contract
 * 
 * This script deploys the LXONLiquidityMining contract to incentivize LP providers
 * with LXON token rewards based on their contribution to LXON trading pairs.
 */
async function main() {
  console.log("🌱 Deploying LXON Liquidity Mining Contract...");
  console.log("===========================================");
  console.log("");

  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log("📝 Deploying with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", ethers.formatEther(balance), "XON");
  console.log("");

  // Configuration
  const config = {
    // LXON token address (update with production address)
    rewardToken: process.env.LXON_TOKEN_ADDRESS || "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c",
    
    // LP token address (update with actual LP token address)
    lpToken: process.env.LP_TOKEN_ADDRESS || "0x0000000000000000000000000000000000000000",
    
    // Reward rate: 100 LXON per day = 100 * 1e18 / 86400 = ~0.0011574 LXON per second
    rewardRate: ethers.parseUnits("100", 18) / BigInt(86400),
    
    // Farming start time: 1 day from now
    farmingStartTime: Math.floor(Date.now() / 1000) + 86400
  };

  console.log("⚙️  Deployment Configuration:");
  console.log("   Reward Token:", config.rewardToken);
  console.log("   LP Token:", config.lpToken);
  console.log("   Reward Rate:", ethers.formatUnits(config.rewardRate, 18), "LXON/second");
  console.log("   Farming Start Time:", new Date(config.farmingStartTime * 1000).toISOString());
  console.log("");

  // Validate LP token address
  if (config.lpToken === "0x0000000000000000000000000000000000000000") {
    console.warn("⚠️  WARNING: LP token address is zero address. Please set LP_TOKEN_ADDRESS environment variable.");
    console.warn("   This deployment will fail without a valid LP token address.");
    console.warn("   Example: LP_TOKEN_ADDRESS=0x... npx hardhat run scripts/deployLiquidityMining.ts --network lxon");
    console.log("");
  }

  // Deploy contract
  console.log("🚀 Deploying LXONLiquidityMining contract...");
  const LiquidityMining = await ethers.getContractFactory("LXONLiquidityMining");
  const liquidityMining = await LiquidityMining.deploy(
    config.rewardToken,
    config.lpToken,
    config.rewardRate,
    config.farmingStartTime
  );

  await liquidityMining.waitForDeployment();
  const liquidityMiningAddress = await liquidityMining.getAddress();
  
  console.log("✅ LXONLiquidityMining deployed to:", liquidityMiningAddress);
  console.log("");

  // Get contract info
  const contractInfo = await liquidityMining.getContractInfo();
  console.log("📊 Contract Information:");
  console.log("   Total Staked:", ethers.formatUnits(contractInfo[0], 18), "LP tokens");
  console.log("   Reward Rate:", ethers.formatUnits(contractInfo[1], 18), "LXON/second");
  console.log("   Farming Start:", new Date(Number(contractInfo[2]) * 1000).toISOString());
  console.log("   Farming End:", new Date(Number(contractInfo[3]) * 1000).toISOString());
  console.log("");

  // Calculate farming duration
  const farmingDuration = Number(contractInfo[3]) - Number(contractInfo[2]);
  const farmingDays = farmingDuration / 86400;
  console.log("📅 Farming Duration:", farmingDays, "days (90 days)");
  console.log("");

  // Calculate total rewards
  const totalRewards = Number(contractInfo[1]) * farmingDuration;
  console.log("💎 Total Rewards Distribution:", ethers.formatUnits(totalRewards, 18), "LXON");
  console.log("");

  // Save deployment info
  const deploymentInfo = {
    contractName: "LXONLiquidityMining",
    address: liquidityMiningAddress,
    deployer: deployer.address,
    deploymentTime: new Date().toISOString(),
    network: (await ethers.provider.getNetwork()).name,
    chainId: (await ethers.provider.getNetwork()).chainId.toString(),
    config: {
      rewardToken: config.rewardToken,
      lpToken: config.lpToken,
      rewardRate: ethers.formatUnits(config.rewardRate, 18),
      farmingStartTime: new Date(config.farmingStartTime * 1000).toISOString(),
      farmingDuration: "90 days"
    },
    contractInfo: {
      totalStaked: ethers.formatUnits(contractInfo[0], 18),
      rewardRate: ethers.formatUnits(contractInfo[1], 18),
      farmingStartTime: new Date(Number(contractInfo[2]) * 1000).toISOString(),
      farmingEndTime: new Date(Number(contractInfo[3]) * 1000).toISOString()
    },
    totalRewards: ethers.formatUnits(totalRewards, 18)
  };

  const fs = require("fs");
  const deploymentPath = "./deployments/liquidity-mining-deployment.json";
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log("💾 Deployment info saved to:", deploymentPath);
  console.log("");

  console.log("🎉 Liquidity Mining Contract Deployment Complete!");
  console.log("===========================================");
  console.log("");
  console.log("📋 Next Steps:");
  console.log("1. Fund the contract with LXON tokens for rewards");
  console.log("2. Set up the LP token address if not already set");
  console.log("3. Create DEX pool for LXON/WETH (or other pair)");
  console.log("4. Launch marketing campaign for liquidity mining");
  console.log("5. Monitor staking activity and rewards distribution");
  console.log("");
  console.log("🔗 Contract Address:", liquidityMiningAddress);
  console.log("📄 Deployment Info:", deploymentPath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });