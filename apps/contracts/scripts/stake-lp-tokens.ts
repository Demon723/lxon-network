import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Staking LP Tokens for Rewards\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';
  const liquidityMiningAddress = '0xe6e082112b270AA9F7B3A0Db36371Eb709f93ecc';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Staker:', targetAddress);
  console.log('Pair:', pairAddress);
  console.log('LiquidityMining:', liquidityMiningAddress);
  console.log('');

  // Get contracts
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const liquidityMining = await ethers.getContractAt('LiquidityMining', liquidityMiningAddress);

  // Check LP token balance
  const lpBalance = await pair.balanceOf(targetAddress);
  console.log('💰 LP Token Balance:', ethers.formatEther(lpBalance));
  console.log('');

  // Approve LiquidityMining to spend LP tokens
  console.log('⏳ Approving LiquidityMining to spend LP tokens...');
  const approveTx = await pair.approve(liquidityMiningAddress, lpBalance);
  await approveTx.wait();
  console.log('✅ LP tokens approved');
  console.log('');

  // First check if pool exists
  const poolLength = await liquidityMining.poolLength();
  console.log('📊 Number of pools:', poolLength);
  console.log('');

  // Add pool if it doesn't exist
  if (poolLength === 0) {
    console.log('⏳ Adding new pool for LP token...');
    try {
      const addPoolTx = await liquidityMining.addPool(pairAddress, 100);
      console.log('Transaction hash:', addPoolTx.hash);
      await addPoolTx.wait();
      console.log('✅ Pool added successfully!');
      console.log('');
    } catch (e: any) {
      console.log('❌ Add pool failed:', e.message);
      console.log('   Owner rights required to add pool');
      return;
    }
  }

  // Set reward token if needed
  console.log('⏳ Setting reward token...');
  try {
    const setRewardTx = await liquidityMining.setPoolRewardToken(0, lxonTokenAddress);
    console.log('Transaction hash:', setRewardTx.hash);
    await setRewardTx.wait();
    console.log('✅ Reward token set!');
    console.log('');
  } catch (e: any) {
    console.log('⚠️ Set reward token failed:', e.message);
    console.log('   May already be set or need owner rights');
    console.log('');
  }

  // Deposit LP tokens (stake)
  console.log('⏳ Depositing (staking) LP tokens...');
  try {
    const depositTx = await liquidityMining.deposit(0, lpBalance);
    console.log('Transaction hash:', depositTx.hash);
    await depositTx.wait();
    console.log('✅ LP tokens staked successfully!');
    console.log('');

    // Check staked balance
    const userInfo = await liquidityMining.userInfo(0, targetAddress);
    console.log('💰 Staked LP Tokens:', ethers.formatEther(userInfo.amount));
    console.log('');

    // Check pending rewards
    const pending = await liquidityMining.pendingReward(0, targetAddress);
    console.log('🎁 Pending Rewards:', ethers.formatEther(pending), 'LXON');
    console.log('');

    console.log('🎉 Staking complete!');
    console.log('');
    console.log('Pool ID: 0');
    console.log('Staked Amount:', ethers.formatEther(userInfo.amount));
    console.log('Rewards Rate: 0.01 LXON/second');
    console.log('Estimated Daily Rewards:', (0.01 * 86400).toFixed(2), 'LXON');

  } catch (error: any) {
    console.log('❌ Error staking:', error.message);
    console.log('');
    console.log('💡 This might be due to:');
    console.log('1. Owner rights required to add pool/set reward token');
    console.log('2. Pool not properly initialized');
    console.log('3. Or deposit function parameters incorrect');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
