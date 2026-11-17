import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Staking LP Tokens with Fixed LiquidityMining\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';
  const liquidityMiningAddress = '0x85e599D3F7Ddd08062c6E5CDdF80556Db4acBc95';

  console.log('Staker:', targetAddress);
  console.log('Pair:', pairAddress);
  console.log('LiquidityMining (NEW):', liquidityMiningAddress);
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
    console.log('Estimated Annual Rewards:', (0.01 * 86400 * 365).toFixed(2), 'LXON');
    console.log('');

    // Wait a bit and check rewards again
    console.log('⏳ Waiting 5 seconds to check reward accumulation...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    const pendingAfter = await liquidityMining.pendingReward(0, targetAddress);
    console.log('🎁 Rewards after 5 seconds:', ethers.formatEther(pendingAfter), 'LXON');
    console.log('Reward increase:', ethers.formatEther(pendingAfter - pending), 'LXON');

  } catch (error: any) {
    console.log('❌ Error staking:', error.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
