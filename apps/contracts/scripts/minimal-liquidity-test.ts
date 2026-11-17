import { ethers } from 'hardhat';

async function main() {
  console.log('🧪 Minimal Liquidity Test with Available Tokens...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load deployment info
  const fs = require('fs');
  const dexPath = './deployments/dex-factory-724.json';
  const dexInfo = JSON.parse(fs.readFileSync(dexPath, 'utf8'));

  const router = await ethers.getContractAt('UniversalRouter', dexInfo.contracts.UniversalRouter);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('Available Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native:', ethers.formatEther(nativeBalance));

  // Use ALL available tokens for minimal liquidity
  const amountLXON = lxonBalance;
  const amountNative = nativeBalance;
  
  console.log('\nUsing ALL available tokens for liquidity:');
  console.log('LXON:', ethers.formatEther(amountLXON));
  console.log('Native:', ethers.formatEther(amountNative));

  if (amountLXON === 0n || amountNative === 0n) {
    console.log('\n❌ One of the balances is zero. Cannot add liquidity.');
    console.log('💡 Solution: Transfer tokens from the owner address (0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5)');
    process.exit(1);
  }

  try {
    // Approve all tokens
    console.log('\n⏳ Approving all tokens...');
    await lxonToken.approve(await router.getAddress(), amountLXON);
    await nativeToken.approve(await router.getAddress(), amountNative);
    console.log('✅ Tokens approved');

    // Add liquidity with minimal slippage (90% tolerance to avoid underflow)
    const deadline = Math.floor(Date.now() / 1000) + 20 * 60;
    console.log('⏳ Adding liquidity (90% slippage tolerance)...');
    
    const addLiquidityTx = await router.addLiquidity(
      lxonAddress,
      nativeTokenAddress,
      amountLXON,
      amountNative,
      amountLXON * 90n / 100n,  // 90% tolerance
      amountNative * 90n / 100n,
      deployer.address,
      deadline
    );
    
    console.log('Transaction hash:', addLiquidityTx.hash);
    const receipt = await addLiquidityTx.wait();
    console.log('✅ Liquidity added!');
    console.log('Gas used:', receipt.gasUsed.toString());

    // Get LP token balance
    const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
    const pair = await ethers.getContractAt('Pair', pairAddress);
    const lpBalance = await pair.balanceOf(deployer.address);
    console.log('LP Tokens received:', ethers.formatEther(lpBalance));

    // Check new reserves
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('New Reserves:');
    console.log('  LXON:', ethers.formatEther(reserve0));
    console.log('  Native:', ethers.formatEther(reserve1));

    console.log('\n🎉 Minimal liquidity added successfully!');
    console.log('💡 Note: This is a very small pool for demonstration purposes.');
    console.log('   For meaningful trading, add significant liquidity (100+ tokens each).');

  } catch (error: any) {
    console.log('❌ Liquidity addition failed:', error.message);
    console.log('\n💡 Alternative approaches:');
    console.log('1. Transfer more tokens from owner address');
    console.log('2. Wait for token distribution from owner');
    console.log('3. Buy tokens on exchanges (if listed)');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
