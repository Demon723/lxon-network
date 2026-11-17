import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Add Available Liquidity to Enable Swap\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const pairAddress = '0x8f8accAFB87D8c8D7cec97DDA25c3E3Dd1f5aB47';

  console.log('Address:', targetAddress);
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

  // Use all available LXON and proportionate WETH
  const lxonAmount = lxonBalance;
  const wethAmount = lxonAmount * 3n / 2n; // 1.5x ratio

  console.log('🔧 Liquidity Amounts:');
  console.log('  LXON:', ethers.formatEther(lxonAmount));
  console.log('  WETH:', ethers.formatEther(wethAmount));
  console.log('');

  if (wethAmount > wethBalance) {
    console.log('⚠️ Insufficient WETH for 1.5x ratio');
    console.log('   Have:', ethers.formatEther(wethBalance));
    console.log('   Need:', ethers.formatEther(wethAmount));
    console.log('');
    console.log('💡 Using available WETH instead');
    console.log('');
    
    // Use all available WETH and proportionate LXON
    const adjustedWethAmount = wethBalance;
    const adjustedLxonAmount = adjustedWethAmount * 2n / 3n;
    
    console.log('🔧 Adjusted Amounts:');
    console.log('  LXON:', ethers.formatEther(adjustedLxonAmount));
    console.log('  WETH:', ethers.formatEther(adjustedWethAmount));
    console.log('');

    // Approve and transfer
    console.log('⏳ Approving and transferring tokens to pair...');
    const lxonApprove = await lxonToken.approve(pairAddress, adjustedLxonAmount);
    await lxonApprove.wait();
    
    const wethApprove = await wethToken.approve(pairAddress, adjustedWethAmount);
    await wethApprove.wait();

    const lxonTransfer = await lxonToken.transfer(pairAddress, adjustedLxonAmount);
    await lxonTransfer.wait();

    const wethTransfer = await wethToken.transfer(pairAddress, adjustedWethAmount);
    await wethTransfer.wait();
    console.log('✅ Tokens transferred to pair');
    console.log('');

    // Mint LP tokens
    console.log('⏳ Minting LP tokens...');
    try {
      const mintTx = await pair.mint(targetAddress);
      console.log('Transaction hash:', mintTx.hash);
      await mintTx.wait();
      console.log('✅ LP tokens minted');
      console.log('');

      // Check reserves
      const [reserve0, reserve1] = await pair.getReserves();
      console.log('📊 New Reserves:');
      console.log('  LXON:', ethers.formatEther(reserve0));
      console.log('  WETH:', ethers.formatEther(reserve1));
      console.log('');

      const lpBalance = await pair.balanceOf(targetAddress);
      console.log('💰 LP Tokens:', ethers.formatEther(lpBalance));
      console.log('');

      console.log('🎉 Liquidity added successfully!');

    } catch (e: any) {
      console.log('❌ Mint failed:', e.message);
    }
  } else {
    // Approve and transfer
    console.log('⏳ Approving and transferring tokens to pair...');
    const lxonApprove = await lxonToken.approve(pairAddress, lxonAmount);
    await lxonApprove.wait();
    
    const wethApprove = await wethToken.approve(pairAddress, wethAmount);
    await wethApprove.wait();

    const lxonTransfer = await lxonToken.transfer(pairAddress, lxonAmount);
    await lxonTransfer.wait();

    const wethTransfer = await wethToken.transfer(pairAddress, wethAmount);
    await wethTransfer.wait();
    console.log('✅ Tokens transferred to pair');
    console.log('');

    // Mint LP tokens
    console.log('⏳ Minting LP tokens...');
    try {
      const mintTx = await pair.mint(targetAddress);
      console.log('Transaction hash:', mintTx.hash);
      await mintTx.wait();
      console.log('✅ LP tokens minted');
      console.log('');

      // Check reserves
      const [reserve0, reserve1] = await pair.getReserves();
      console.log('📊 New Reserves:');
      console.log('  LXON:', ethers.formatEther(reserve0));
      console.log('  WETH:', ethers.formatEther(reserve1));
      console.log('');

      const lpBalance = await pair.balanceOf(targetAddress);
      console.log('💰 LP Tokens:', ethers.formatEther(lpBalance));
      console.log('');

      console.log('🎉 Liquidity added successfully!');

    } catch (e: any) {
      console.log('❌ Mint failed:', e.message);
    }
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
