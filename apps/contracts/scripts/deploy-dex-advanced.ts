import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Deploying Advanced DEX Features (Price Oracle & Liquidity Mining)...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);

  // Deploy PriceOracle
  console.log('\n📦 Deploying PriceOracle...');
  const PriceOracle = await ethers.deployContract('PriceOracle');
  await PriceOracle.waitForDeployment();
  const oracleAddress = await PriceOracle.getAddress();
  console.log('✅ PriceOracle deployed to:', oracleAddress);

  // Deploy LiquidityMining
  console.log('\n📦 Deploying LiquidityMining...');
  const rewardPerSecond = ethers.parseEther('0.01'); // 0.01 LXON per second
  const startTime = Math.floor(Date.now() / 1000);
  const duration = 365 * 24 * 60 * 60; // 1 year
  
  const LiquidityMining = await ethers.deployContract('LiquidityMining', [
    rewardPerSecond,
    startTime,
    duration
  ]);
  await LiquidityMining.waitForDeployment();
  const miningAddress = await LiquidityMining.getAddress();
  console.log('✅ LiquidityMining deployed to:', miningAddress);

  // Save deployment info
  const network = await ethers.provider.getNetwork();
  const deploymentInfo = {
    network: network.name,
    chainId: Number(network.chainId),
    deployer: deployer.address,
    contracts: {
      PriceOracle: oracleAddress,
      LiquidityMining: miningAddress,
    },
    config: {
      rewardPerSecond: rewardPerSecond.toString(),
      startTime: startTime,
      duration: duration,
      endTime: startTime + duration,
    },
    deployedAt: new Date().toISOString(),
  };

  const fs = require('fs');
  const dir = './deployments';
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${dir}/dex-advanced-${Number(network.chainId)}.json`, JSON.stringify(deploymentInfo, null, 2));

  console.log('\n🎉 Advanced DEX Features Deployed!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  PriceOracle: ${oracleAddress}`);
  console.log(`  LiquidityMining: ${miningAddress}`);
  console.log(`  Reward Rate: ${ethers.formatEther(rewardPerSecond)} LXON/second`);
  console.log(`  Mining Duration: 1 year`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('\n📝 Next Steps:');
  console.log('  1. Add price feeds to oracle');
  console.log('  2. Add liquidity pools to mining contract');
  console.log('  3. Set reward tokens for each pool');
  console.log('  4. Start liquidity mining program');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
