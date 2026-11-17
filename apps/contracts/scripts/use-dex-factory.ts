import { ethers } from 'hardhat';

async function main() {
  console.log('🔄 Using DEX Factory - Creating Pairs and Swapping...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load deployment info
  const fs = require('fs');
  const deploymentPath = './deployments/dex-factory-724.json'; // LXON native blockchain
  if (!fs.existsSync(deploymentPath)) {
    console.error('❌ Deployment file not found. Run deploy-dex-factory.ts first.');
    process.exit(1);
  }

  const deploymentInfo = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
  console.log('DEXFactory:', deploymentInfo.contracts.DEXFactory);
  console.log('UniversalRouter:', deploymentInfo.contracts.UniversalRouter);

  // Get contracts
  const factory = await ethers.getContractAt('DEXFactory', deploymentInfo.contracts.DEXFactory);
  const router = await ethers.getContractAt('UniversalRouter', deploymentInfo.contracts.UniversalRouter);

  // Token addresses for LXON native blockchain
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('\n📦 Creating LXON/NativeToken trading pair...');
  const createPairTx = await router.createPair(lxonAddress, nativeTokenAddress);
  await createPairTx.wait();
  console.log('✅ Pair created!');

  // Get pair address
  const pairAddress = await factory.getPair(lxonAddress, nativeTokenAddress);
  console.log('Pair address:', pairAddress);

  // Check pair info
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const [reserve0, reserve1] = await pair.getReserves();
  console.log('Reserves:', {
    token0: ethers.formatEther(reserve0),
    token1: ethers.formatEther(reserve1),
  });

  console.log('\n💡 Example: Add liquidity (requires both tokens)');
  console.log('  router.addLiquidity(lxonAddress, nativeTokenAddress, amountA, amountB, ...)');

  console.log('\n💡 Example: Swap LXON for NativeToken');
  console.log('  router.swapExactTokensForTokens(amountIn, amountOutMin, [lxonAddress, nativeTokenAddress], to, deadline)');

  console.log('\n🎉 DEX Factory is now operational on LXON Native Blockchain!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Features:');
  console.log('  ✅ Dynamic pair creation');
  console.log('  ✅ Multi-token support (any ERC20 pair)');
  console.log('  ✅ Liquidity provision');
  console.log('  ✅ Token swapping with slippage protection');
  console.log('  ✅ Direct swaps (no multi-hop yet)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
