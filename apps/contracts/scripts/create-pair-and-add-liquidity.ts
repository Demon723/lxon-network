import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Creating Pair and Adding Liquidity\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const routerAddress = '0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75';
  const factoryAddress = '0xf8B86d766b718188458c6867576bec4D74866813';

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
  const router = await ethers.getContractAt('UniversalRouter', routerAddress);
  const factory = await ethers.getContractAt('DEXFactory', factoryAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const nativeBalance = await nativeToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  Native:', ethers.formatEther(nativeBalance));
  console.log('');

  // Use 50% of available LXON for liquidity
  const lxonAmount = lxonBalance / 2n;
  const nativeAmount = nativeBalance;
  
  console.log('🔧 Liquidity Amounts:');
  console.log('  LXON:', ethers.formatEther(lxonAmount));
  console.log('  Native:', ethers.formatEther(nativeAmount));
  console.log('');

  // Step 1: Create pair
  console.log('⏳ Creating LXON/Native pair...');
  try {
    const createTx = await router.createPair(lxonTokenAddress, nativeTokenAddress);
    console.log('Transaction hash:', createTx.hash);
    await createTx.wait();
    console.log('✅ Pair created successfully!');
  } catch (e: any) {
    console.log('Pair might already exist:', e.message);
  }
  console.log('');

  // Step 2: Approve tokens
  console.log('⏳ Approving LXON token...');
  const lxonApprove = await lxonToken.approve(routerAddress, lxonAmount);
  await lxonApprove.wait();
  console.log('✅ LXON approved');

  console.log('⏳ Approving Native token...');
  const nativeApprove = await nativeToken.approve(routerAddress, nativeAmount);
  await nativeApprove.wait();
  console.log('✅ Native token approved');
  console.log('');

  // Step 3: Add liquidity
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  console.log('⏳ Adding liquidity...');
  try {
    const tx = await router.addLiquidity(
      lxonTokenAddress,
      nativeTokenAddress,
      lxonAmount,
      nativeAmount,
      lxonAmount * 99n / 100n,
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
    console.log('DEX is now ready for trading!');

  } catch (error: any) {
    console.log('❌ Error adding liquidity:', error.message);
    console.log('');
    console.log('💡 Amounts might still be too small');
    console.log('   The native token amount is very small');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
