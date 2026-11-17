import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Wrapping ETH and Adding Liquidity\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const routerAddress = '0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75';

  console.log('Strategy: Wrap ETH → WETH → Add liquidity with LXON');
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);
  const router = await ethers.getContractAt('UniversalRouter', routerAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const ethBalance = await ethers.provider.getBalance(targetAddress);
  const wethBalance = await wethToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  ETH:', ethers.formatEther(ethBalance));
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('');

  // Wrap 1,500 ETH to WETH
  const ethToWrap = ethers.parseEther('1500');
  const lxonAmount = ethers.parseEther('1000');
  
  console.log('🔧 Amounts:');
  console.log('  ETH to wrap:', ethers.formatEther(ethToWrap));
  console.log('  LXON for liquidity:', ethers.formatEther(lxonAmount));
  console.log('');

  if (ethBalance < ethToWrap) {
    console.log('❌ Insufficient ETH balance');
    return;
  }

  console.log('✅ Sufficient ETH balance');
  console.log('');

  // Wrap ETH to WETH
  console.log('⏳ Wrapping ETH to WETH...');
  try {
    const wethInterface = new ethers.Interface([
      'function deposit() payable'
    ]);
    
    const wrapTx = await deployer.sendTransaction({
      to: wethAddress,
      data: wethInterface.encodeFunctionData('deposit'),
      value: ethToWrap
    });
    
    console.log('Transaction hash:', wrapTx.hash);
    await wrapTx.wait();
    console.log('✅ ETH wrapped to WETH successfully!');
    
    const newWethBalance = await wethToken.balanceOf(targetAddress);
    console.log('New WETH Balance:', ethers.formatEther(newWethBalance));
  } catch (e: any) {
    console.log('❌ Wrap failed:', e.message);
    console.log('   WETH contract might not support deposit()');
    return;
  }
  console.log('');

  // Approve WETH
  console.log('⏳ Approving WETH...');
  const wethApprove = await wethToken.approve(routerAddress, ethToWrap);
  await wethApprove.wait();
  console.log('✅ WETH approved');
  console.log('');

  // Approve LXON
  console.log('⏳ Approving LXON...');
  const lxonApprove = await lxonToken.approve(routerAddress, lxonAmount);
  await lxonApprove.wait();
  console.log('✅ LXON approved');
  console.log('');

  // Add liquidity
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  console.log('⏳ Adding liquidity...');
  try {
    const tx = await router.addLiquidity(
      lxonTokenAddress,
      wethAddress,
      lxonAmount,
      ethToWrap,
      lxonAmount * 99n / 100n,
      ethToWrap * 99n / 100n,
      targetAddress,
      deadline
    );

    console.log('Transaction hash:', tx.hash);
    console.log('⏳ Waiting for confirmation...');
    const receipt = await tx.wait();
    console.log('✅ Liquidity added successfully!');
    console.log('Gas used:', receipt.gasUsed.toString());
    console.log('');

    // Check reserves
    const pairAddress = await router.getPair(lxonTokenAddress, wethAddress);
    const pair = await ethers.getContractAt('Pair', pairAddress);
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('📊 Reserves:');
    console.log('  LXON:', ethers.formatEther(reserve0));
    console.log('  WETH:', ethers.formatEther(reserve1));
    console.log('');

    const lpBalance = await pair.balanceOf(targetAddress);
    console.log('💰 LP Tokens:', ethers.formatEther(lpBalance));
    console.log('');

    console.log('🎉 Liquidity added successfully!');

  } catch (error: any) {
    console.log('❌ Error adding liquidity:', error.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
