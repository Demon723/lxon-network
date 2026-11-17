import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Funding LiquidityMining with LXON for Rewards\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const liquidityMiningAddress = '0x85e599D3F7Ddd08062c6E5CDdF80556Db4acBc95';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Funder:', targetAddress);
  console.log('LiquidityMining:', liquidityMiningAddress);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check current balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const contractBalance = await lxonToken.balanceOf(liquidityMiningAddress);

  console.log('💰 Current Balances:');
  console.log('  Your LXON:', ethers.formatEther(lxonBalance));
  console.log('  Contract LXON:', ethers.formatEther(contractBalance));
  console.log('');

  // Calculate funding amount (1 year of rewards at 0.01 LXON/second)
  const oneYearSeconds = 365 * 24 * 60 * 60;
  const rewardPerSecond = ethers.parseEther('0.01');
  const fundingAmount = rewardPerSecond * BigInt(oneYearSeconds);

  console.log('🔧 Funding Amount:');
  console.log('  Duration: 1 year');
  console.log('  Rate: 0.01 LXON/second');
  console.log('  Total:', ethers.formatEther(fundingAmount), 'LXON');
  console.log('  USD Value:', '$', (Number(ethers.formatEther(fundingAmount)) * 1.5).toFixed(2));
  console.log('');

  if (lxonBalance < fundingAmount) {
    console.log('❌ Insufficient LXON balance');
    console.log('   Have:', ethers.formatEther(lxonBalance));
    console.log('   Need:', ethers.formatEther(fundingAmount));
    console.log('');
    console.log('💡 Funding with available balance instead...');
    console.log('');
    
    // Fund with available balance
    const fundTx = await lxonToken.transfer(liquidityMiningAddress, lxonBalance);
    console.log('Transaction hash:', fundTx.hash);
    await fundTx.wait();
    console.log('✅ Funded with all available LXON:', ethers.formatEther(lxonBalance));
  } else {
    console.log('⏳ Funding LiquidityMining contract...');
    const fundTx = await lxonToken.transfer(liquidityMiningAddress, fundingAmount);
    console.log('Transaction hash:', fundTx.hash);
    await fundTx.wait();
    console.log('✅ Contract funded successfully!');
  }
  console.log('');

  // Check new balance
  const newContractBalance = await lxonToken.balanceOf(liquidityMiningAddress);
  console.log('💰 New Contract Balance:', ethers.formatEther(newContractBalance));
  console.log('');

  // Calculate duration funded
  const secondsFunded = Number(newContractBalance) / Number(rewardPerSecond);
  const daysFunded = secondsFunded / 86400;
  console.log('⏰ Duration Funded:', daysFunded.toFixed(2), 'days');
  console.log('');

  console.log('🎉 Funding complete!');
  console.log('');
  console.log('Rewards can now be claimed by stakers!');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
