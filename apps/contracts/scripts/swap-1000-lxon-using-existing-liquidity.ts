import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Swap 1000 LXON Using Existing Pair Liquidity\n');
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

  // Swap 1000 LXON using existing liquidity
  const lxonToSwap = ethers.parseEther('1000');

  if (lxonBalance < lxonToSwap) {
    console.log('❌ Insufficient LXON balance');
    console.log('   Have:', ethers.formatEther(lxonBalance));
    console.log('   Need:', ethers.formatEther(lxonToSwap));
    return;
  }

  console.log('⏳ Swapping 1000 LXON → WETH using existing liquidity...');
  console.log('');

  try {
    // Approve pair to spend LXON
    const approveTx = await lxonToken.approve(pairAddress, lxonToSwap);
    await approveTx.wait();
    console.log('✅ LXON approved');
    console.log('');

    // Calculate expected output
    const amountOut = await pair.getAmountOut(lxonToSwap, reserve0, reserve1);
    console.log('Expected WETH out:', ethers.formatEther(amountOut));
    console.log('');

    // Transfer LXON to pair
    const transferTx = await lxonToken.transfer(pairAddress, lxonToSwap);
    await transferTx.wait();
    console.log('✅ LXON transferred to pair');
    console.log('');

    // Execute swap
    const swapTx = await pair.swap(0, amountOut, targetAddress);
    console.log('Transaction hash:', swapTx.hash);
    await swapTx.wait();
    console.log('✅ Swap executed');
    console.log('');

    // Check WETH received
    const newWethBalance = await wethToken.balanceOf(targetAddress);
    const wethReceived = newWethBalance - wethBalance;
    
    console.log('💰 WETH received:', ethers.formatEther(wethReceived));
    console.log('USD Value: $', (Number(ethers.formatEther(wethReceived)) * 1.5).toFixed(2));
    console.log('');

    // Transfer to founder
    if (wethReceived > 0) {
      console.log('⏳ Transferring WETH to founder...');
      const transferTx = await wethToken.transfer(founderAddress, wethReceived);
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
      console.log('  Swapped: 1000 LXON');
      console.log('  Received:', ethers.formatEther(wethReceived), 'WETH');
      console.log('  Sent to:', founderAddress);
      console.log('  USD Value: $', (Number(ethers.formatEther(wethReceived)) * 1.5).toFixed(2));
    } else {
      console.log('⚠️ No WETH received from swap');
    }

  } catch (e: any) {
    console.log('❌ Error:', e.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
