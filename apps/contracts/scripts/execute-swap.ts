import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Executing LXON → WETH Swap\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';

  console.log('Swapper:', targetAddress);
  console.log('Founder:', founderAddress);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('WETH Token:', wethAddress);
  console.log('Pair:', pairAddress);
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const wethBalance = await wethToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('');

  // Check pair reserves
  const [reserve0, reserve1] = await pair.getReserves();
  console.log('📊 Pair Reserves:');
  console.log('  Reserve 0:', ethers.formatEther(reserve0));
  console.log('  Reserve 1:', ethers.formatEther(reserve1));
  console.log('');

  // Calculate swap amount
  const lxonAmountIn = ethers.parseEther('1000');
  console.log('🔧 Swap Amount:');
  console.log('  LXON to swap:', ethers.formatEther(lxonAmountIn));
  console.log('');

  // Calculate expected output
  const amountOut = await pair.getAmountOut(lxonAmountIn, reserve0, reserve1);
  console.log('📈 Expected Output:');
  console.log('  WETH out:', ethers.formatEther(amountOut));
  console.log('  Exchange rate:', (Number(ethers.formatEther(amountOut)) / Number(ethers.formatEther(lxonAmountIn))).toFixed(4), 'WETH/LXON');
  console.log('');

  // Approve pair to spend LXON
  console.log('⏳ Approving pair to spend LXON...');
  const approveTx = await lxonToken.approve(pairAddress, lxonAmountIn);
  await approveTx.wait();
  console.log('✅ LXON approved');
  console.log('');

  // Execute swap
  console.log('⏳ Executing swap...');
  try {
    const swapTx = await pair.swap(0, amountOut, targetAddress);
    console.log('Transaction hash:', swapTx.hash);
    await swapTx.wait();
    console.log('✅ Swap executed successfully!');
    console.log('');

    // Check new balances
    const newLxonBalance = await lxonToken.balanceOf(targetAddress);
    const newWethBalance = await wethToken.balanceOf(targetAddress);
    
    console.log('💰 New Balances:');
    console.log('  LXON:', ethers.formatEther(newLxonBalance));
    console.log('  WETH:', ethers.formatEther(newWethBalance));
    console.log('');

    const lxonSpent = lxonBalance - newLxonBalance;
    const wethReceived = newWethBalance - wethBalance;
    
    console.log('📊 Swap Summary:');
    console.log('  LXON spent:', ethers.formatEther(lxonSpent));
    console.log('  WETH received:', ethers.formatEther(wethReceived));
    console.log('');

    // Send WETH to founder
    console.log('⏳ Sending WETH to founder...');
    const sendTx = await wethToken.transfer(founderAddress, wethReceived);
    console.log('Transaction hash:', sendTx.hash);
    await sendTx.wait();
    console.log('✅ WETH sent to founder!');
    console.log('');

    const founderWethBalance = await wethToken.balanceOf(founderAddress);
    console.log('💰 Founder WETH Balance:', ethers.formatEther(founderWethBalance));
    console.log('');

    console.log('🎉 Swap and transfer complete!');
    console.log('');
    console.log('Summary:');
    console.log('  Swapped:', ethers.formatEther(lxonSpent), 'LXON');
    console.log('  Received:', ethers.formatEther(wethReceived), 'WETH');
    console.log('  Sent to:', founderAddress);
    console.log('  USD Value: $', (Number(ethers.formatEther(wethReceived)) * 1.5).toFixed(2), '(at $1.50/WETH)');

  } catch (error: any) {
    console.log('❌ Error executing swap:', error.message);
    console.log('');
    console.log('💡 This might be due to:');
    console.log('1. Pair expects swap to be called from router');
    console.log('2. Need to use UniversalRouter instead');
    console.log('3. Or swap parameters are incorrect');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
