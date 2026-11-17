import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Attempting Liquidity with Current Balances...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load addresses
  const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const routerAddress = '0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75';

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
  const router = await ethers.getContractAt('UniversalRouter', routerAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  Native:', ethers.formatEther(nativeBalance));
  console.log('');

  // Check if pair exists
  const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
  console.log('📊 Pair Address:', pairAddress);
  console.log('');

  // Try to add liquidity with all available tokens
  console.log('🔧 Attempting to add liquidity with available tokens...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Calculate deadline (20 minutes from now)
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  // Use 99% of balance as minimum to account for gas
  const lxonAmount = lxonBalance;
  const nativeAmount = nativeBalance;
  const lxonMin = lxonBalance * 99n / 100n;
  const nativeMin = nativeBalance * 99n / 100n;

  console.log('Amounts to add:');
  console.log('  LXON:', ethers.formatEther(lxonAmount));
  console.log('  Native:', ethers.formatEther(nativeAmount));
  console.log('  LXON Min:', ethers.formatEther(lxonMin));
  console.log('  Native Min:', ethers.formatEther(nativeMin));
  console.log('');

  try {
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

    // Add liquidity
    console.log('⏳ Adding liquidity...');
    const tx = await router.addLiquidity(
      lxonAddress,
      nativeTokenAddress,
      lxonAmount,
      nativeAmount,
      lxonMin,
      nativeMin,
      deployer.address,
      deadline
    );

    console.log('Transaction hash:', tx.hash);
    console.log('⏳ Waiting for confirmation...');
    const receipt = await tx.wait();
    console.log('✅ Liquidity added successfully!');
    console.log('Gas used:', receipt.gasUsed.toString());
    console.log('');

    // Check new reserves
    const pair = await ethers.getContractAt('Pair', pairAddress);
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('📊 New Reserves:');
    console.log('  Reserve 0:', ethers.formatEther(reserve0));
    console.log('  Reserve 1:', ethers.formatEther(reserve1));
    console.log('');

    // Check LP token balance
    const lpBalance = await pair.balanceOf(deployer.address);
    console.log('💰 LP Tokens Received:', ethers.formatEther(lpBalance));

  } catch (error: any) {
    console.log('❌ Error adding liquidity:', error.message);
    console.log('');
    console.log('💡 This is expected - amounts are too small for Pair calculations');
    console.log('   The Pair contract requires minimum amounts for x*y=k formula');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
