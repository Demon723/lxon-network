import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Execute 1000 LXON → USD Swap and Transfer to Founder\n');
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
  const ethBalance = await ethers.provider.getBalance(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  Native ETH:', ethers.formatEther(ethBalance));
  console.log('');

  // Step 1: Wrap 1,500 ETH to WETH
  const ethToWrap = ethers.parseEther('1500');
  const lxonForSwap = ethers.parseEther('1000');

  console.log('⏳ Step 1: Wrapping 1,500 ETH to WETH...');
  if (ethBalance < ethToWrap) {
    console.log('❌ Insufficient ETH balance');
    console.log('   Have:', ethers.formatEther(ethBalance));
    console.log('   Need:', ethers.formatEther(ethToWrap));
    return;
  }

  try {
    const wethInterface = new ethers.Interface(['function deposit() payable']);
    const wrapTx = await deployer.sendTransaction({
      to: wethAddress,
      data: wethInterface.encodeFunctionData('deposit'),
      value: ethToWrap
    });
    console.log('Transaction hash:', wrapTx.hash);
    await wrapTx.wait();
    console.log('✅ ETH wrapped to WETH');
    console.log('');

    const wethBalance = await wethToken.balanceOf(targetAddress);
    console.log('💰 WETH Balance:', ethers.formatEther(wethBalance));
    console.log('');

    // Step 2: Add liquidity to pair
    console.log('⏳ Step 2: Adding liquidity to pair...');
    console.log('  LXON:', ethers.formatEther(lxonForSwap));
    console.log('  WETH:', ethers.formatEther(ethToWrap));
    console.log('');

    const lxonApprove = await lxonToken.approve(pairAddress, lxonForSwap);
    await lxonApprove.wait();

    const wethApprove = await wethToken.approve(pairAddress, ethToWrap);
    await wethApprove.wait();

    const lxonTransfer = await lxonToken.transfer(pairAddress, lxonForSwap);
    await lxonTransfer.wait();

    const wethTransfer = await wethToken.transfer(pairAddress, ethToWrap);
    await wethTransfer.wait();
    console.log('✅ Tokens transferred to pair');
    console.log('');

    const mintTx = await pair.mint(targetAddress);
    console.log('Transaction hash:', mintTx.hash);
    await mintTx.wait();
    console.log('✅ LP tokens minted');
    console.log('');

    // Check new reserves
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('📊 New Reserves:');
    console.log('  LXON:', ethers.formatEther(reserve0));
    console.log('  WETH:', ethers.formatEther(reserve1));
    console.log('');

    // Step 3: Execute swap
    console.log('⏳ Step 3: Executing 1000 LXON → WETH swap...');
    const amountOut = await pair.getAmountOut(lxonForSwap, reserve0, reserve1);
    console.log('Expected WETH out:', ethers.formatEther(amountOut));
    console.log('');

    const swapTx = await pair.swap(0, amountOut, targetAddress);
    console.log('Transaction hash:', swapTx.hash);
    await swapTx.wait();
    console.log('✅ Swap executed');
    console.log('');

    const finalWethBalance = await wethToken.balanceOf(targetAddress);
    const wethFromSwap = finalWethBalance - ethToWrap; // Subtract the WETH we wrapped
    
    console.log('💰 WETH from swap:', ethers.formatEther(wethFromSwap));
    console.log('USD Value: $', (Number(ethers.formatEther(wethFromSwap)) * 1.5).toFixed(2));
    console.log('');

    // Step 4: Transfer to founder
    console.log('⏳ Step 4: Transferring WETH to founder...');
    const transferTx = await wethToken.transfer(founderAddress, wethFromSwap);
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
    console.log('  Received:', ethers.formatEther(wethFromSwap), 'WETH');
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
