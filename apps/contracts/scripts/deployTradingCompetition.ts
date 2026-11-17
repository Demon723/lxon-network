import { ethers } from "hardhat";

/**
 * Deploy LXON Trading Competition Contract
 * 
 * This script deploys the LXONTradingCompetition contract to reward high-volume
 * traders with LXON tokens based on their trading volume in LXON pairs.
 */
async function main() {
  console.log("🏆 Deploying LXON Trading Competition Contract...");
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
    
    // Trading token address (usually same as reward token for LXON)
    tradingToken: process.env.TRADING_TOKEN_ADDRESS || "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c",
    
    // Reward pool: 100,000 LXON for the competition
    rewardPool: ethers.parseUnits("100000", 18),
    
    // Competition start time: 1 day from now
    startTime: Math.floor(Date.now() / 1000) + 86400
  };

  console.log("⚙️  Deployment Configuration:");
  console.log("   Reward Token:", config.rewardToken);
  console.log("   Trading Token:", config.tradingToken);
  console.log("   Reward Pool:", ethers.formatUnits(config.rewardPool, 18), "LXON");
  console.log("   Competition Start:", new Date(config.startTime * 1000).toISOString());
  console.log("");

  // Deploy contract
  console.log("🚀 Deploying LXONTradingCompetition contract...");
  const TradingCompetition = await ethers.getContractFactory("LXONTradingCompetition");
  const tradingCompetition = await TradingCompetition.deploy(
    config.rewardToken,
    config.tradingToken,
    config.rewardPool,
    config.startTime
  );

  await tradingCompetition.waitForDeployment();
  const tradingCompetitionAddress = await tradingCompetition.getAddress();
  
  console.log("✅ LXONTradingCompetition deployed to:", tradingCompetitionAddress);
  console.log("");

  // Get contract info
  const contractInfo = await tradingCompetition.getContractInfo();
  console.log("📊 Contract Information:");
  console.log("   Total Volume Traded:", ethers.formatUnits(contractInfo[0], 6), "LXON");
  console.log("   Total Participants:", contractInfo[1].toString());
  console.log("   Competition Start:", new Date(Number(contractInfo[2]) * 1000).toISOString());
  console.log("   Competition End:", new Date(Number(contractInfo[3]) * 1000).toISOString());
  console.log("   Total Reward Pool:", ethers.formatUnits(contractInfo[4], 18), "LXON");
  console.log("");

  // Get reward tiers
  const tierCount = await tradingCompetition.getRewardTierCount();
  console.log("🏅 Reward Tiers:");
  for (let i = 0; i < tierCount; i++) {
    const [minVolume, rewardPercentage] = await tradingCompetition.getRewardTier(i);
    const volumeInLXON = Number(minVolume) / 1e6;
    const percentage = Number(rewardPercentage) / 100;
    const tierReward = (Number(config.rewardPool) * Number(rewardPercentage)) / 10000;
    console.log(`   Tier ${i + 1}: ${volumeInLXON.toLocaleString()}+ LXON - ${percentage}% of pool (${ethers.formatUnits(tierReward, 18)} LXON)`);
  }
  console.log("");

  // Calculate competition duration
  const competitionDuration = Number(contractInfo[3]) - Number(contractInfo[2]);
  const competitionDays = competitionDuration / 86400;
  console.log("📅 Competition Duration:", competitionDays, "days (30 days)");
  console.log("");

  // Save deployment info
  const deploymentInfo = {
    contractName: "LXONTradingCompetition",
    address: tradingCompetitionAddress,
    deployer: deployer.address,
    deploymentTime: new Date().toISOString(),
    network: (await ethers.provider.getNetwork()).name,
    chainId: (await ethers.provider.getNetwork()).chainId.toString(),
    config: {
      rewardToken: config.rewardToken,
      tradingToken: config.tradingToken,
      rewardPool: ethers.formatUnits(config.rewardPool, 18),
      competitionStartTime: new Date(config.startTime * 1000).toISOString(),
      competitionDuration: "30 days"
    },
    contractInfo: {
      totalVolumeTraded: ethers.formatUnits(contractInfo[0], 6),
      totalParticipants: contractInfo[1].toString(),
      competitionStartTime: new Date(Number(contractInfo[2]) * 1000).toISOString(),
      competitionEndTime: new Date(Number(contractInfo[3]) * 1000).toISOString(),
      totalRewardPool: ethers.formatUnits(contractInfo[4], 18)
    },
    rewardTiers: []
  };

  for (let i = 0; i < tierCount; i++) {
    const [minVolume, rewardPercentage] = await tradingCompetition.getRewardTier(i);
    const volumeInLXON = Number(minVolume) / 1e6;
    const percentage = Number(rewardPercentage) / 100;
    const tierReward = (Number(config.rewardPool) * Number(rewardPercentage)) / 10000;
    deploymentInfo.rewardTiers.push({
      tier: i + 1,
      minVolume: volumeInLXON,
      rewardPercentage: percentage,
      tierReward: ethers.formatUnits(tierReward, 18)
    });
  }

  const fs = require("fs");
  const deploymentPath = "./deployments/trading-competition-deployment.json";
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log("💾 Deployment info saved to:", deploymentPath);
  console.log("");

  console.log("🎉 Trading Competition Contract Deployment Complete!");
  console.log("===========================================");
  console.log("");
  console.log("📋 Next Steps:");
  console.log("1. Fund the contract with LXON tokens for rewards");
  console.log("2. Set up trade recording mechanism (DEX integration)");
  console.log("3. Launch marketing campaign for trading competition");
  console.log("4. Monitor trading activity and leaderboard");
  console.log("5. Prepare for reward distribution after competition ends");
  console.log("");
  console.log("🔗 Contract Address:", tradingCompetitionAddress);
  console.log("📄 Deployment Info:", deploymentPath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });