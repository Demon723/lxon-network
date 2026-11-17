import { ethers } from "hardhat";

/**
 * Fund Trading Volume Contracts
 * 
 * This script funds the LXONLiquidityMining and LXONTradingCompetition contracts
 * with LXON tokens for rewards distribution.
 */
async function main() {
  console.log("💰 Funding Trading Volume Contracts...");
  console.log("===========================================");
  console.log("");

  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log("📝 Funding from account:", deployer.address);
  console.log("");

  // Load deployment info
  const fs = require("fs");
  
  let liquidityMiningAddress: string;
  let tradingCompetitionAddress: string;
  let lxonTokenAddress: string;

  try {
    const lmDeployment = JSON.parse(fs.readFileSync("./deployments/liquidity-mining-deployment.json", "utf8"));
    liquidityMiningAddress = lmDeployment.address;
    lxonTokenAddress = lmDeployment.config.rewardToken;
    console.log("📄 Loaded Liquidity Mining deployment from:", liquidityMiningAddress);
  } catch (error) {
    console.error("❌ Liquidity Mining deployment not found. Please deploy it first.");
    process.exit(1);
  }

  try {
    const tcDeployment = JSON.parse(fs.readFileSync("./deployments/trading-competition-deployment.json", "utf8"));
    tradingCompetitionAddress = tcDeployment.address;
    console.log("📄 Loaded Trading Competition deployment from:", tradingCompetitionAddress);
  } catch (error) {
    console.error("❌ Trading Competition deployment not found. Please deploy it first.");
    process.exit(1);
  }

  console.log("");

  // Get LXON token contract
  const lxonToken = await ethers.getContractAt("IERC20", lxonTokenAddress);
  const lxonSymbol = await lxonToken.symbol();
  console.log("🪙 LXON Token:", lxonSymbol, "at", lxonTokenAddress);
  console.log("");

  // Check deployer balance
  const deployerBalance = await lxonToken.balanceOf(deployer.address);
  console.log("💰 Deployer Balance:", ethers.formatUnits(deployerBalance, 18), lxonSymbol);
  console.log("");

  // Funding configuration
  const fundingConfig = {
    // Liquidity Mining: 50,000 LXON for 90-day farming
    liquidityMining: ethers.parseUnits("50000", 18),
    
    // Trading Competition: 100,000 LXON for 30-day competition
    tradingCompetition: ethers.parseUnits("100000", 18)
  };

  const totalFunding = fundingConfig.liquidityMining + fundingConfig.tradingCompetition;
  console.log("⚙️  Funding Configuration:");
  console.log("   Liquidity Mining:", ethers.formatUnits(fundingConfig.liquidityMining, 18), lxonSymbol);
  console.log("   Trading Competition:", ethers.formatUnits(fundingConfig.tradingCompetition, 18), lxonSymbol);
  console.log("   Total Funding:", ethers.formatUnits(totalFunding, 18), lxonSymbol);
  console.log("");

  // Check if sufficient balance
  if (deployerBalance < totalFunding) {
    console.error("❌ Insufficient LXON balance for funding.");
    console.error("   Required:", ethers.formatUnits(totalFunding, 18), lxonSymbol);
    console.error("   Available:", ethers.formatUnits(deployerBalance, 18), lxonSymbol);
    process.exit(1);
  }

  console.log("✅ Sufficient balance available for funding");
  console.log("");

  // Fund Liquidity Mining contract
  console.log("💸 Funding Liquidity Mining contract...");
  const lmTx = await lxonToken.transfer(liquidityMiningAddress, fundingConfig.liquidityMining);
  await lmTx.wait();
  console.log("✅ Liquidity Mining funded:", ethers.formatUnits(fundingConfig.liquidityMining, 18), lxonSymbol);
  console.log("   Transaction:", lmTx.hash);
  console.log("");

  // Verify Liquidity Mining balance
  const lmBalance = await lxonToken.balanceOf(liquidityMiningAddress);
  console.log("💰 Liquidity Mining Balance:", ethers.formatUnits(lmBalance, 18), lxonSymbol);
  console.log("");

  // Fund Trading Competition contract
  console.log("💸 Funding Trading Competition contract...");
  const tcTx = await lxonToken.transfer(tradingCompetitionAddress, fundingConfig.tradingCompetition);
  await tcTx.wait();
  console.log("✅ Trading Competition funded:", ethers.formatUnits(fundingConfig.tradingCompetition, 18), lxonSymbol);
  console.log("   Transaction:", tcTx.hash);
  console.log("");

  // Verify Trading Competition balance
  const tcBalance = await lxonToken.balanceOf(tradingCompetitionAddress);
  console.log("💰 Trading Competition Balance:", ethers.formatUnits(tcBalance, 18), lxonSymbol);
  console.log("");

  // Verify remaining balance
  const remainingBalance = await lxonToken.balanceOf(deployer.address);
  console.log("💰 Remaining Balance:", ethers.formatUnits(remainingBalance, 18), lxonSymbol);
  console.log("");

  // Save funding info
  const fundingInfo = {
    fundingTime: new Date().toISOString(),
    funder: deployer.address,
    lxonToken: lxonTokenAddress,
    contracts: {
      liquidityMining: {
        address: liquidityMiningAddress,
        funded: ethers.formatUnits(fundingConfig.liquidityMining, 18),
        balance: ethers.formatUnits(lmBalance, 18),
        transaction: lmTx.hash
      },
      tradingCompetition: {
        address: tradingCompetitionAddress,
        funded: ethers.formatUnits(fundingConfig.tradingCompetition, 18),
        balance: ethers.formatUnits(tcBalance, 18),
        transaction: tcTx.hash
      }
    },
    totalFunded: ethers.formatUnits(totalFunding, 18),
    remainingBalance: ethers.formatUnits(remainingBalance, 18)
  };

  const fundingPath = "./deployments/trading-volume-funding.json";
  fs.writeFileSync(fundingPath, JSON.stringify(fundingInfo, null, 2));
  console.log("💾 Funding info saved to:", fundingPath);
  console.log("");

  console.log("🎉 Trading Volume Contracts Funding Complete!");
  console.log("===========================================");
  console.log("");
  console.log("📋 Next Steps:");
  console.log("1. Set up LP token address for Liquidity Mining");
  console.log("2. Set up DEX integration for trade recording");
  console.log("3. Launch marketing campaigns for both programs");
  console.log("4. Monitor staking and trading activity");
  console.log("5. Adjust reward rates if needed");
  console.log("");
  console.log("💰 Total Funded:", ethers.formatUnits(totalFunding, 18), lxonSymbol);
  console.log("📄 Funding Info:", fundingPath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });