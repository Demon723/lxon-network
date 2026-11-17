import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Swap WETH → LXON → WETH to Execute 1000 LXON Swap\n');
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

  // Step 1: Swap WETH to LXON to get 1000 LXON
  // Need to calculate how much WETH to swap to get 1000 LXON
  // Using the AMM formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
  // Rearranging for amountIn when we know amountOut is complex, so we'll estimate
  const lxonTarget = ethers.parseEther('1000');
  const wethToSwap = ethers.parseEther('1300'); // Estimate - should get ~1000 LXON

  console.log('⏳ Step 1: Swapping WETH → LXON to get 1000 LXON');
  console.log('  WETH to swap:', ethers.formatEther(wethToSwap));
  console.log('');

  if (wethBalance < wethToSwap) {
    console.log('❌ Insufficient WETH balance');
    console.log('   Have:', ethers.formatEther(wethBalance));
    console.log('   Need:', ethers.formatEther(wethToSwap));
    return;
  }

  try {
    const approveTx = await wethToken.approve(pairAddress, wethToSwap);
    await approveTx.wait();

    const swapTx = await pair.swap(wethToSwap, 0, targetAddress);
    console.log('Transaction hash:', swapTx.hash);
    await swapTx.wait();
    console.log('✅ WETH → LXON swap complete');
    console.log('');

    const newLxonBalance = await lxonToken.balanceOf(targetAddress);
    const newWethBalance = await wethToken.balanceOf(targetAddress);
    
    console.log('💰 Balances after WETH → LXON swap:');
    console.log('  LXON:', ethers.formatEther(newLxonBalance));
    console.log('  WETH:', ethers.formatEther(newWethBalance));
    console.log('');

    // Step 2: Now swap 1000 LXON → WETH
    const lxonToSwap = newLxonBalance < lxonTarget ? newLxonBalance : lxonTarget;
    console.log('⏳ Step 2: Swapping LXON → WETH');
    console.log('  LXON to swap:', ethers.formatEther(lxonToSwap));
    console.log('');

    const lxonApproveTx = await lxonToken.approve(pairAddress, lxonToSwap);
    await lxonApprove.wait();

    const [reserve0_2, reserve1_2] = await pair.getReserves();
    const amountOut = await pair.getAmountOut(lxonToSwap, reserve0_2, reserve1_2);

    const swap2Tx = await pair.swap(0, amountOut, targetAddress);
    console.log('Transaction hash:', swap2Tx.hash);
    await swap2Tx.wait();
    console.log('✅ LXON → WETH swap complete');
    console.log('');

    const finalWethBalance = await wethToken.balanceOf(targetAddress);
    const wethFromSwap = finalWethBalance - newWethBalance;
    
    console.log('💰 Final WETH Balance:', ethers.formatEther(finalWethBalance));
    console.log('📊 WETH from LXON swap:', ethers.formatEther(wethFromSwap));
    console.log('  USD Value: $', (Number(ethers.formatEther(wethFromSwap)) * 1.5).toFixed(2));
    console.log('');

    // Step 3: Transfer to founder
    console.log('⏳ Step 3: Transferring WETH to founder...');
    const transferTx = await wethToken.transfer(founderAddress, wethFromSwap);
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
    console.log('  LXON swapped:', ethers.formatEther(lxonToSwap));
    console.log('  WETH received:', ethers.formatEther(wethFromSwap));
    console.log('  Sent to:', founderAddress);
    console.log('  USD Value: $', (Number(ethers.formatEther(wethFromSwap)) * 1.5).toFixed(2));

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
