import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Adding Liquidity with LXON and Native ETH\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E'; // WETH/Native
  const routerAddress = '0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75';
  const factoryAddress = '0xf8B86d766b718188458c6867576bec4D74866813';

  console.log('Using Native ETH as quote token instead of Native token contract');
  console.log('');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const router = await ethers.getContractAt('UniversalRouter', routerAddress);
  const factory = await ethers.getContractAt('DEXFactory', factoryAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const ethBalance = await ethers.provider.getBalance(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  Native ETH:', ethers.formatEther(ethBalance));
  console.log('');

  // Use 1,000 LXON and 1,500 ETH for liquidity
  const lxonAmount = ethers.parseEther('1000');
  const ethAmount = ethers.parseEther('1500');
  
  console.log('🔧 Liquidity Amounts:');
  console.log('  LXON:', ethers.formatEther(lxonAmount));
  console.log('  ETH:', ethers.formatEther(ethAmount));
  console.log('');

  // Check if we have enough
  if (lxonBalance < lxonAmount) {
    console.log('❌ Insufficient LXON balance');
    console.log('   Have:', ethers.formatEther(lxonBalance));
    console.log('   Need:', ethers.formatEther(lxonAmount));
    return;
  }

  if (ethBalance < ethAmount) {
    console.log('❌ Insufficient ETH balance');
    console.log('   Have:', ethers.formatEther(ethBalance));
    console.log('   Need:', ethers.formatEther(ethAmount));
    return;
  }

  console.log('✅ Sufficient balances for liquidity');
  console.log('');

  // Create LXON/ETH pair
  console.log('⏳ Creating LXON/ETH pair...');
  try {
    const createTx = await router.createPair(lxonTokenAddress, wethAddress);
    console.log('Transaction hash:', createTx.hash);
    await createTx.wait();
    console.log('✅ Pair created successfully!');
  } catch (e: any) {
    console.log('Pair might already exist:', e.message);
  }
  console.log('');

  // Approve LXON tokens
  console.log('⏳ Approving LXON token...');
  const lxonApprove = await lxonToken.approve(routerAddress, lxonAmount);
  await lxonApprove.wait();
  console.log('✅ LXON approved');
  console.log('');

  // Calculate deadline (20 minutes)
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  // Add liquidity
  console.log('⏳ Adding liquidity...');
  try {
    const tx = await router.addLiquidity(
      lxonTokenAddress,
      wethAddress,
      lxonAmount,
      ethAmount,
      lxonAmount * 99n / 100n,
      ethAmount * 99n / 100n,
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
    const pairAddress = await router.getPair(lxonTokenAddress, wethAddress);
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
    console.log('💡 This might be due to:');
    console.log('1. Router expects ERC20 tokens, not native ETH');
    console.log('2. Need to wrap ETH first');
    console.log('3. Or use a different approach');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
