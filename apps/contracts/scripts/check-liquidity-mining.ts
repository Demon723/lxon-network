import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 LiquidityMining Diagnostic Check\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const liquidityMiningAddress = '0x85e599D3F7Ddd08062c6E5CDdF80556Db4acBc95';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  const liquidityMining = await ethers.getContractAt('LiquidityMining', liquidityMiningAddress);
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  console.log('Checking LiquidityMining contract state...\n');

  // Check pool info
  const poolInfo = await liquidityMining.poolInfo(0);
  console.log('📊 Pool Info:');
  console.log('  LP Token:', poolInfo.lpToken);
  console.log('  Reward Token:', poolInfo.rewardToken);
  console.log('  Alloc Point:', poolInfo.allocPoint.toString());
  console.log('  Total Staked:', ethers.formatEther(poolInfo.totalStaked));
  console.log('  Last Reward Time:', poolInfo.lastRewardTime.toString());
  console.log('  Acc Reward Per Share:', poolInfo.accRewardPerShare.toString());
  console.log('');

  // Check user info
  const userInfo = await liquidityMining.userInfo(0, targetAddress);
  console.log('👤 User Info:');
  console.log('  Amount:', ethers.formatEther(userInfo.amount));
  console.log('  Reward Debt:', userInfo.rewardDebt.toString());
  console.log('  Pending Rewards:', ethers.formatEther(userInfo.pendingRewards));
  console.log('');

  // Check pending rewards (calculated)
  const pending = await liquidityMining.pendingReward(0, targetAddress);
  console.log('💰 Calculated Pending Rewards:', ethers.formatEther(pending));
  console.log('');

  // Check contract settings
  const rewardPerSecond = await liquidityMining.rewardPerSecond();
  const startTime = await liquidityMining.startTime();
  const endTime = await liquidityMining.endTime();
  console.log('⚙️ Contract Settings:');
  console.log('  Reward Per Second:', ethers.formatEther(rewardPerSecond), 'LXON');
  console.log('  Start Time:', new Date(Number(startTime) * 1000).toISOString());
  console.log('  End Time:', new Date(Number(endTime) * 1000).toISOString());
  console.log('');

  // Check contract LXON balance
  const contractBalance = await lxonToken.balanceOf(liquidityMiningAddress);
  console.log('💰 Contract LXON Balance:', ethers.formatEther(contractBalance));
  console.log('');

  // Check current time
  const currentTime = Math.floor(Date.now() / 1000);
  console.log('⏰ Current Time:', new Date(currentTime * 1000).toISOString());
  console.log('Time Since Start:', currentTime - Number(startTime), 'seconds');
  console.log('');

  console.log('🔍 Analysis:');
  if (contractBalance === 0n) {
    console.log('❌ ISSUE: Contract has 0 LXON balance to pay rewards');
    console.log('   Solution: Fund contract with LXON tokens for rewards');
  } else if (poolInfo.rewardToken === ethers.ZeroAddress) {
    console.log('❌ ISSUE: Reward token not set');
  } else {
    console.log('✅ All checks passed');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
