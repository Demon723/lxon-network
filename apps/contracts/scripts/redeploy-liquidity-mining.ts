import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Redeploying LiquidityMining with Bug Fix\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';

  console.log('Deployer:', deployer.address);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('Pair:', pairAddress);
  console.log('');

  // Deploy new LiquidityMining contract
  console.log('⏳ Deploying new LiquidityMining contract...');
  console.log('   Bug fix: updatePool now allows first deposit');
  console.log('   Reward rate: 0.01 LXON/second');
  console.log('');

  const rewardPerSecond = ethers.parseEther('0.01');
  const startTime = Math.floor(Date.now() / 1000);
  const duration = 365 * 24 * 60 * 60; // 1 year

  const LiquidityMining = await ethers.getContractFactory('LiquidityMining');
  const liquidityMining = await LiquidityMining.deploy(
    rewardPerSecond,
    startTime,
    duration
  );
  await liquidityMining.waitForDeployment();
  const liquidityMiningAddress = await liquidityMining.getAddress();
  
  console.log('✅ LiquidityMining deployed at:', liquidityMiningAddress);
  console.log('');

  // Add pool
  console.log('⏳ Adding pool for LP token...');
  const addPoolTx = await liquidityMining.addPool(pairAddress, 100);
  console.log('Transaction hash:', addPoolTx.hash);
  await addPoolTx.wait();
  console.log('✅ Pool added successfully!');
  console.log('');

  // Set reward token
  console.log('⏳ Setting reward token to LXON...');
  const setRewardTx = await liquidityMining.setPoolRewardToken(0, lxonTokenAddress);
  console.log('Transaction hash:', setRewardTx.hash);
  await setRewardTx.wait();
  console.log('✅ Reward token set!');
  console.log('');

  console.log('🎉 LiquidityMining redeployment complete!');
  console.log('');
  console.log('New Address:', liquidityMiningAddress);
  console.log('Pool ID: 0');
  console.log('Reward Token:', lxonTokenAddress);
  console.log('Reward Rate: 0.01 LXON/second');
  console.log('Duration: 1 year');
  console.log('');
  console.log('Next steps:');
  console.log('1. Update scripts to use new address');
  console.log('2. Stake LP tokens');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
