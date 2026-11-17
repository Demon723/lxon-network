import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Transfer Available WETH to Founder\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Address:', targetAddress);
  console.log('Founder:', founderAddress);
  console.log('');

  // Get contracts
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);

  // Check current balances
  const wethBalance = await wethToken.balanceOf(targetAddress);

  console.log('💰 Current WETH Balance:', ethers.formatEther(wethBalance));
  console.log('USD Value: $', (Number(ethers.formatEther(wethBalance)) * 1.5).toFixed(2));
  console.log('');

  if (wethBalance > 0) {
    console.log('⏳ Transferring WETH to founder...');
    const transferTx = await wethToken.transfer(founderAddress, wethBalance);
    console.log('Transaction hash:', transferTx.hash);
    await transferTx.wait();
    console.log('✅ Transfer complete');
    console.log('');

    const founderWethBalance = await wethToken.balanceOf(founderAddress);
    console.log('💰 Founder WETH Balance:', ethers.formatEther(founderWethBalance));
    console.log('Total USD Value: $', (Number(ethers.formatEther(founderWethBalance)) * 1.5).toFixed(2));
    console.log('');

    console.log('🎉 Complete!');
    console.log('');
    console.log('Summary:');
    console.log('  Transferred:', ethers.formatEther(wethBalance), 'WETH');
    console.log('  To:', founderAddress);
    console.log('  USD Value: $', (Number(ethers.formatEther(wethBalance)) * 1.5).toFixed(2));
    console.log('');
    console.log('Note: This WETH was obtained from previous swap operations');
  } else {
    console.log('❌ No WETH available to transfer');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
