import { ethers } from 'hardhat';

async function main() {
  console.log('⚙️ Setting Up Advanced DEX Features...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load deployment info
  const fs = require('fs');
  const dexPath = './deployments/dex-factory-724.json';
  const advancedPath = './deployments/dex-advanced-724.json';
  
  const dexInfo = JSON.parse(fs.readFileSync(dexPath, 'utf8'));
  const advancedInfo = JSON.parse(fs.readFileSync(advancedPath, 'utf8'));

  // Get contracts
  const oracle = await ethers.getContractAt('PriceOracle', advancedInfo.contracts.PriceOracle);
  const mining = await ethers.getContractAt('LiquidityMining', advancedInfo.contracts.LiquidityMining);
  const router = await ethers.getContractAt('UniversalRouter', dexInfo.contracts.UniversalRouter);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('PriceOracle:', advancedInfo.contracts.PriceOracle);
  console.log('LiquidityMining:', advancedInfo.contracts.LiquidityMining);
  console.log('LXON:', lxonAddress);
  console.log('Native Token:', nativeTokenAddress);

  // Setup Price Oracle
  console.log('\n📊 Setting up Price Oracle...');
  
  // Set LXON price ($1.50 USD with 18 decimals)
  const lxonPrice = ethers.parseUnits('1.5', 18);
  const tx1 = await oracle.updatePrice(lxonAddress, lxonPrice, 18);
  await tx1.wait();
  console.log('✅ LXON price set: $1.50');

  // Set Native Token price (assuming $1.00 USD)
  const nativePrice = ethers.parseUnits('1.0', 18);
  const tx2 = await oracle.updatePrice(nativeTokenAddress, nativePrice, 18);
  await tx2.wait();
  console.log('✅ Native Token price set: $1.00');

  // Get LXON/Native pair price
  const pairPrice = await oracle.getPairPrice(lxonAddress, nativeTokenAddress);
  console.log('📈 LXON/Native Price:', ethers.formatUnits(pairPrice, 18));

  // Setup Liquidity Mining
  console.log('\n💰 Setting up Liquidity Mining...');
  
  // Get the LP token address
  const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
  console.log('LP Token:', pairAddress);

  // Add liquidity pool
  const allocPoint = 100; // 100% allocation (only one pool)
  await mining.addPool(pairAddress, allocPoint);
  console.log('✅ Liquidity pool added with 100 alloc points');

  // Set reward token (LXON)
  await mining.setPoolRewardToken(0, lxonAddress);
  console.log('✅ Reward token set to LXON');

  // Calculate USD value example
  console.log('\n💡 Price Oracle Examples:');
  const amountToPrice = ethers.parseEther('1000');
  const usdValue = await oracle.getPriceInUSD(lxonAddress, amountToPrice);
  console.log('1000 LXON = $' + ethers.formatUnits(usdValue, 18));

  console.log('\n🎉 Advanced DEX Features Configured!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log('  ✅ Price Oracle configured with LXON and Native Token prices');
  console.log('  ✅ Liquidity Mining pool added for LXON/Native pair');
  console.log('  ✅ Reward rate: 0.01 LXON/second');
  console.log('  ✅ Duration: 1 year');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('\n📝 Usage:');
  console.log('  mining.deposit(0, lpTokenAmount) - Stake LP tokens');
  console.log('  mining.claimReward(0) - Claim LXON rewards');
  console.log('  oracle.getPrice(token) - Get token price');
  console.log('  oracle.getPriceInUSD(token, amount) - Get USD value');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
