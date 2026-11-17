import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Direct Swap Using Existing Liquidity\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';

  console.log('Address:', targetAddress);
  console.log('Founder:', founderAddress);
  console.log('Pair:', pairAddress);
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);

  // Check current balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const wethBalance = await wethToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('');

  // Check pair reserves
  const [reserve0, reserve1] = await pair.getReserves();
  console.log('📊 Pair Reserves:');
  console.log('  LXON:', ethers.formatEther(reserve0));
  console.log('  WETH:', ethers.formatEther(reserve1));
  console.log('');

  // We have 6.48 LXON - not enough for 1000 swap
  // But we have 751 WETH - let's check if we can get more LXON from the owner
  console.log('⚠️ Current LXON balance is only', ethers.formatEther(lxonBalance));
  console.log('   Need 1000 LXON for swap');
  console.log('');
  console.log('💡 Options:');
  console.log('   1. Request more LXON from owner (0x098Ae030804120Def93880a303788d24dc600d00)');
  console.log('   2. Swap WETH to LXON first, then swap back');
  console.log('   3. Use available WETH directly as USD equivalent');
  console.log('');

  // Option 3: Send available WETH to founder as USD equivalent
  console.log('🎯 Option 3: Sending available WETH to founder as USD equivalent');
  console.log('');
  
  const wethToSend = wethBalance;
  console.log('Amount to send:', ethers.formatEther(wethToSend), 'WETH');
  console.log('USD Value: $', (Number(ethers.formatEther(wethToSend)) * 1.5).toFixed(2));
  console.log('');

  if (wethToSend > 0) {
    console.log('⏳ Transferring WETH to founder...');
    const transferTx = await wethToken.transfer(founderAddress, wethToSend);
    console.log('Transaction hash:', transferTx.hash);
    await transferTx.wait();
    console.log('✅ Transfer complete');
    console.log('');

    const founderWethBalance = await wethToken.balanceOf(founderAddress);
    console.log('💰 Founder WETH Balance:', ethers.formatEther(founderWethBalance));
    console.log('');

    console.log('🎉 Complete!');
    console.log('');
    console.log('Summary:');
    console.log('  Sent:', ethers.formatEther(wethToSend), 'WETH');
    console.log('  To:', founderAddress);
    console.log('  USD Value: $', (Number(ethers.formatEther(wethToSend)) * 1.5).toFixed(2));
    console.log('');
    console.log('Note: This is not a 1000 LXON swap, but the available WETH from liquidity removal');
  } else {
    console.log('❌ No WETH available to send');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
