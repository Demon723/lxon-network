import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Claiming Staking Rewards\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const liquidityMiningAddress = '0x85e599D3F7Ddd08062c6E5CDdF80556Db4acBc95';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Claimer:', targetAddress);
  console.log('LiquidityMining:', liquidityMiningAddress);
  console.log('');

  // Get contracts
  const liquidityMining = await ethers.getContractAt('LiquidityMining', liquidityMiningAddress);
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check pending rewards
  const pending = await liquidityMining.pendingReward(0, targetAddress);
  console.log('💰 Pending Rewards:', ethers.formatEther(pending), 'LXON');
  console.log('');

  // Check current LXON balance
  const currentBalance = await lxonToken.balanceOf(targetAddress);
  console.log('💰 Current LXON Balance:', ethers.formatEther(currentBalance));
  console.log('');

  // Claim rewards
  console.log('⏳ Claiming rewards...');
  try {
    const claimTx = await liquidityMining.claimReward(0);
    console.log('Transaction hash:', claimTx.hash);
    await claimTx.wait();
    console.log('✅ Rewards claimed successfully!');
    console.log('');

    // Check new balance
    const newBalance = await lxonToken.balanceOf(targetAddress);
    console.log('💰 New LXON Balance:', ethers.formatEther(newBalance));
    console.log('');

    const rewardsReceived = newBalance - currentBalance;
    console.log('🎁 Rewards Received:', ethers.formatEther(rewardsReceived), 'LXON');
    console.log('USD Value:', '$', (Number(ethers.formatEther(rewardsReceived)) * 1.5).toFixed(2));
    console.log('');

    console.log('🎉 Claim complete!');

  } catch (error: any) {
    console.log('❌ Error claiming:', error.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
