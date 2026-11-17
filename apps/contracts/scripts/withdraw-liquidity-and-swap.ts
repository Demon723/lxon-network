import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Withdraw Liquidity and Swap 1000 LXON to USD\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';
  const liquidityMiningAddress = '0x85e599D3F7Ddd08062c6E5CDdF80556Db4acBc95';

  console.log('Address:', targetAddress);
  console.log('Founder:', founderAddress);
  console.log('Pair:', pairAddress);
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const liquidityMining = await ethers.getContractAt('LiquidityMining', liquidityMiningAddress);

  // Check current balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const wethBalance = await wethToken.balanceOf(targetAddress);
  const lpBalance = await pair.balanceOf(targetAddress);
  const stakedBalance = await liquidityMining.userInfo(0, targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('  LP Tokens (wallet):', ethers.formatEther(lpBalance));
  console.log('  LP Tokens (staked):', ethers.formatEther(stakedBalance.amount));
  console.log('');

  // Step 1: Withdraw from staking
  if (stakedBalance.amount > 0) {
    console.log('⏳ Step 1: Withdrawing LP tokens from staking...');
    try {
      const withdrawTx = await liquidityMining.withdraw(0, stakedBalance.amount);
      console.log('Transaction hash:', withdrawTx.hash);
      await withdrawTx.wait();
      console.log('✅ LP tokens withdrawn from staking');
      console.log('');
    } catch (e: any) {
      console.log('❌ Withdraw failed:', e.message);
      return;
    }
  }

  // Check updated LP balance
  const updatedLpBalance = await pair.balanceOf(targetAddress);
  console.log('💰 LP Tokens after staking withdrawal:', ethers.formatEther(updatedLpBalance));
  console.log('');

  // Step 2: Remove liquidity from pair
  console.log('⏳ Step 2: Removing liquidity from pair...');
  try {
    const removeLiquidityTx = await pair.burn(targetAddress);
    console.log('Transaction hash:', removeLiquidityTx.hash);
    await removeLiquidityTx.wait();
    console.log('✅ Liquidity removed from pair');
    console.log('');
  } catch (e: any) {
    console.log('❌ Remove liquidity failed:', e.message);
    console.log('   Pair might require calling from router');
    return;
  }

  // Check new token balances
  const newLxonBalance = await lxonToken.balanceOf(targetAddress);
  const newWethBalance = await wethToken.balanceOf(targetAddress);
  
  console.log('💰 Balances after removing liquidity:');
  console.log('  LXON:', ethers.formatEther(newLxonBalance));
  console.log('  WETH:', ethers.formatEther(newWethBalance));
  console.log('');

  const lxonReceived = newLxonBalance - lxonBalance;
  const wethReceived = newWethBalance - wethBalance;
  
  console.log('📊 Tokens received from liquidity removal:');
  console.log('  LXON:', ethers.formatEther(lxonReceived));
  console.log('  WETH:', ethers.formatEther(wethReceived));
  console.log('');

  // Step 3: Check if we have 1000 LXON
  if (newLxonBalance < ethers.parseEther('1000')) {
    console.log('⚠️ Insufficient LXON for 1000 swap');
    console.log('   Have:', ethers.formatEther(newLxonBalance));
    console.log('   Need: 1000');
    console.log('');
    console.log('💡 Will swap available LXON instead');
    console.log('');
  }

  // Step 4: Add liquidity back for swap
  const lxonForSwap = newLxonBalance < ethers.parseEther('1000') ? newLxonBalance : ethers.parseEther('1000');
  const wethForSwap = lxonForSwap * 3n / 2n; // 1.5x ratio

  console.log('⏳ Step 3: Adding liquidity back for swap...');
  try {
    const lxonApprove = await lxonToken.approve(pairAddress, lxonForSwap);
    await lxonApprove.wait();
    
    const wethApprove = await wethToken.approve(pairAddress, wethForSwap);
    await wethApprove.wait();

    const lxonTransfer = await lxonToken.transfer(pairAddress, lxonForSwap);
    await lxonTransfer.wait();

    const wethTransfer = await wethToken.transfer(pairAddress, wethForSwap);
    await wethTransfer.wait();

    const mintTx = await pair.mint(targetAddress);
    await mintTx.wait();
    console.log('✅ Liquidity added back');
    console.log('');
  } catch (e: any) {
    console.log('❌ Add liquidity failed:', e.message);
    return;
  }

  // Step 5: Execute swap
  console.log('⏳ Step 4: Executing LXON → WETH swap...');
  try {
    const [reserve0, reserve1] = await pair.getReserves();
    const amountOut = await pair.getAmountOut(lxonForSwap, reserve0, reserve1);
    
    const approveTx = await lxonToken.approve(pairAddress, lxonForSwap);
    await approveTx.wait();

    const swapTx = await pair.swap(0, amountOut, targetAddress);
    console.log('Transaction hash:', swapTx.hash);
    await swapTx.wait();
    console.log('✅ Swap executed');
    console.log('');

    const finalWethBalance = await wethToken.balanceOf(targetAddress);
    const wethFromSwap = finalWethBalance - newWethBalance;
    
    console.log('📊 Swap Results:');
    console.log('  LXON swapped:', ethers.formatEther(lxonForSwap));
    console.log('  WETH received:', ethers.formatEther(wethFromSwap));
    console.log('  Exchange rate:', (Number(ethers.formatEther(wethFromSwap)) / Number(ethers.formatEther(lxonForSwap))).toFixed(4), 'WETH/LXON');
    console.log('  USD Value: $', (Number(ethers.formatEther(wethFromSwap)) * 1.5).toFixed(2));
    console.log('');

    // Step 6: Transfer to founder
    console.log('⏳ Step 5: Transferring WETH to founder...');
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
    console.log('  Swapped:', ethers.formatEther(lxonForSwap), 'LXON');
    console.log('  Received:', ethers.formatEther(wethFromSwap), 'WETH');
    console.log('  Sent to:', founderAddress);
    console.log('  USD Value: $', (Number(ethers.formatEther(wethFromSwap)) * 1.5).toFixed(2));

  } catch (e: any) {
    console.log('❌ Swap failed:', e.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
