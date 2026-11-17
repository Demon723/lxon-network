import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Adding Liquidity to DEX\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const routerAddress = '0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75';

  console.log('Your Address:', targetAddress);
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
  const router = await ethers.getContractAt('UniversalRouter', routerAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const nativeBalance = await nativeToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  Native:', ethers.formatEther(nativeBalance));
  console.log('');

  // Use 1000 LXON for liquidity (keep 9000 for swap)
  const lxonAmount = ethers.parseEther('1000');
  const nativeAmount = ethers.parseEther('1500'); // 1.5 ratio at $1.50/LXON
  
  console.log('🔧 Adding Liquidity:');
  console.log('  LXON Amount:', ethers.formatEther(lxonAmount));
  console.log('  Native Amount:', ethers.formatEther(nativeAmount));
  console.log('');

  // Check if we have enough
  if (lxonBalance < lxonAmount) {
    console.log('❌ Insufficient LXON balance');
    console.log('   Have:', ethers.formatEther(lxonBalance));
    console.log('   Need:', ethers.formatEther(lxonAmount));
    return;
  }

  if (nativeBalance < nativeAmount) {
    console.log('❌ Insufficient Native balance');
    console.log('   Have:', ethers.formatEther(nativeBalance));
    console.log('   Need:', ethers.formatEther(nativeAmount));
    return;
  }

  console.log('✅ Sufficient balances for liquidity');
  console.log('');

  // Approve tokens
  console.log('⏳ Approving LXON token...');
  const lxonApprove = await lxonToken.approve(routerAddress, lxonAmount);
  await lxonApprove.wait();
  console.log('✅ LXON approved');

  console.log('⏳ Approving Native token...');
  const nativeApprove = await nativeToken.approve(routerAddress, nativeAmount);
  await nativeApprove.wait();
  console.log('✅ Native token approved');
  console.log('');

  // Calculate deadline (20 minutes)
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  // Add liquidity
  console.log('⏳ Adding liquidity...');
  try {
    const tx = await router.addLiquidity(
      lxonTokenAddress,
      nativeTokenAddress,
      lxonAmount,
      nativeAmount,
      lxonAmount * 99n / 100n, // 1% slippage
      nativeAmount * 99n / 100n,
      targetAddress,
      deadline
    );

    console.log('Transaction hash:', tx.hash);
    console.log('⏳ Waiting for confirmation...');
    const receipt = await tx.wait();
    console.log('✅ Liquidity added successfully!');
    console.log('Gas used:', receipt.gasUsed.toString());
    console.log('');

    // Check new reserves
    const pairAddress = await router.getPair(lxonTokenAddress, nativeTokenAddress);
    const pair = await ethers.getContractAt('Pair', pairAddress);
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('📊 New Reserves:');
    console.log('  Reserve 0:', ethers.formatEther(reserve0));
    console.log('  Reserve 1:', ethers.formatEther(reserve1));
    console.log('');

    // Check LP token balance
    const lpBalance = await pair.balanceOf(targetAddress);
    console.log('💰 LP Tokens Received:', ethers.formatEther(lpBalance));
    console.log('');

    console.log('🎉 Liquidity addition complete!');
    console.log('Ready for swap operations!');

  } catch (error: any) {
    console.log('❌ Error adding liquidity:', error.message);
    console.log('');
    console.log('💡 This might be due to:');
    console.log('1. Pair doesn\'t exist (need to create first)');
    console.log('2. Small amounts causing arithmetic issues');
    console.log('3. Router configuration issues');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
