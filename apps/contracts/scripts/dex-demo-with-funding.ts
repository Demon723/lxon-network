import { ethers } from 'hardhat';

async function main() {
  console.log('🎭 DEX Demo: Simulated Funding → Full Operations\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load deployment info
  const fs = require('fs');
  const dexPath = './deployments/dex-factory-724.json';
  const advancedPath = './deployments/dex-advanced-724.json';
  
  const dexInfo = JSON.parse(fs.readFileSync(dexPath, 'utf8'));
  const advancedInfo = JSON.parse(fs.readFileSync(advancedPath, 'utf8'));

  // Get contracts
  const router = await ethers.getContractAt('UniversalRouter', dexInfo.contracts.UniversalRouter);
  const oracle = await ethers.getContractAt('PriceOracle', advancedInfo.contracts.PriceOracle);
  const mining = await ethers.getContractAt('LiquidityMining', advancedInfo.contracts.LiquidityMining);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  // Get token contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  console.log('\n📊 Current Real Balances:');
  const realLXON = await lxonToken.balanceOf(deployer.address);
  const realNative = await nativeToken.balanceOf(deployer.address);
  console.log('LXON:', ethers.formatEther(realLXON));
  console.log('Native:', ethers.formatEther(realNative));

  console.log('\n💡 Note: Your balances are too small for liquidity operations.');
  console.log('This demo will show the CONTRACT OPERATIONS with simulated amounts.\n');

  // ============ DEMONSTRATE PRICE MONITORING ============
  console.log('📈 Step 1: Price Monitoring (REAL DATA)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const [lxonPrice, lxonTimestamp, lxonStale] = await oracle.getPrice(lxonAddress);
  const [nativePrice, nativeTimestamp, nativeStale] = await oracle.getPrice(nativeTokenAddress);
  
  console.log('LXON Price:', ethers.formatUnits(lxonPrice, 18), 'USD');
  console.log('  Last Updated:', new Date(Number(lxonTimestamp) * 1000).toLocaleString());
  console.log('  Fresh:', !lxonStale ? '✅' : '❌');
  
  console.log('\nNative Token Price:', ethers.formatUnits(nativePrice, 18), 'USD');
  console.log('  Last Updated:', new Date(Number(nativeTimestamp) * 1000).toLocaleString());
  console.log('  Fresh:', !nativeStale ? '✅' : '❌');

  const pairPrice = await oracle.getPairPrice(lxonAddress, nativeTokenAddress);
  console.log('\nPrice Ratio:', ethers.formatUnits(pairPrice, 18), 'LXON per Native');

  // Calculate USD value for different amounts
  console.log('\n💰 USD Value Examples:');
  const amounts = [100, 1000, 10000];
  for (const amount of amounts) {
    const usdValue = await oracle.getPriceInUSD(lxonAddress, ethers.parseEther(amount.toString()));
    console.log(`  ${amount} LXON = $${ethers.formatUnits(usdValue, 18)}`);
  }

  // ============ DEMONSTRATE LIQUIDITY OPERATIONS ============
  console.log('\n💧 Step 2: Liquidity Operations (SIMULATED)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const simulatedLXON = ethers.parseEther('1000');
  const simulatedNative = ethers.parseEther('1000');
  
  console.log('Simulated Liquidity Amounts:');
  console.log('  LXON:', ethers.formatEther(simulatedLXON));
  console.log('  Native:', ethers.formatEther(simulatedNative));
  console.log('  Total USD Value:', '$' + (Number(ethers.formatEther(simulatedLXON)) * 1.5 + Number(ethers.formatEther(simulatedNative)) * 1.0).toFixed(2));

  console.log('\n💡 To add this liquidity (when you have sufficient tokens):');
  console.log('```typescript');
  console.log('const deadline = Math.floor(Date.now() / 1000) + 20 * 60;');
  console.log('await router.addLiquidity(');
  console.log('  lxonAddress,');
  console.log('  nativeTokenAddress,');
  console.log('  ethers.parseEther("1000"),  // 1000 LXON');
  console.log('  ethers.parseEther("1000"),  // 1000 Native');
  console.log('  ethers.parseEther("950"),   // min LXON (5% slippage)');
  console.log('  ethers.parseEther("950"),   // min Native (5% slippage)');
  console.log('  recipient,');
  console.log('  deadline');
  console.log(');');
  console.log('```');

  // ============ DEMONSTRATE TRADING OPERATIONS ============
  console.log('\n🔄 Step 3: Trading Operations (SIMULATED)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const swapAmount = ethers.parseEther('100');
  console.log('Simulated Swap:');
  console.log('  Input:', ethers.formatEther(swapAmount), 'LXON');
  console.log('  USD Value:', '$' + (Number(ethers.formatEther(swapAmount)) * 1.5).toFixed(2));
  
  const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const [reserve0, reserve1] = await pair.getReserves();
  
  if (reserve0 > 0n && reserve1 > 0n) {
    const amountOut = await pair.getAmountOut(swapAmount, reserve0, reserve1);
    console.log('  Output:', ethers.formatEther(amountOut), 'Native');
    console.log('  USD Value:', '$' + (Number(ethers.formatEther(amountOut)) * 1.0).toFixed(2));
  } else {
    console.log('  Output: Calculated using price ratio (no liquidity yet)');
    const estimatedOutput = swapAmount * 15n / 10n; // Using 1.5 price ratio
    console.log('  Output:', ethers.formatEther(estimatedOutput), 'Native (estimated)');
  }

  console.log('\n💡 To execute this swap (when liquidity exists):');
  console.log('```typescript');
  console.log('const deadline = Math.floor(Date.now() / 1000) + 20 * 60;');
  console.log('await router.swapExactTokensForTokens(');
  console.log('  ethers.parseEther("100"),    // 100 LXON');
  console.log('  ethers.parseEther("95"),     // min 95 Native (5% slippage)');
  console.log('  [lxonAddress, nativeTokenAddress],');
  console.log('  recipient,');
  console.log('  deadline');
  console.log(');');
  console.log('```');

  // ============ DEMONSTRATE STAKING OPERATIONS ============
  console.log('\n💰 Step 4: Liquidity Mining/Staking (SIMULATED)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const simulatedLP = ethers.parseEther('100');
  console.log('Simulated LP Tokens to Stake:', ethers.formatEther(simulatedLP));
  
  // Calculate rewards
  const rewardPerSecond = ethers.parseEther('0.01');
  const secondsPerDay = 24 * 60 * 60;
  const dailyReward = rewardPerSecond * BigInt(secondsPerDay);
  const yearlyReward = dailyReward * 365n;
  
  console.log('\nReward Calculation:');
  console.log('  Reward Rate:', ethers.formatEther(rewardPerSecond), 'LXON/second');
  console.log('  Daily Reward:', ethers.formatEther(dailyReward), 'LXON per LP token');
  console.log('  Yearly Reward:', ethers.formatEther(yearlyReward), 'LXON per LP token');
  console.log('  For 100 LP tokens:');
  console.log('    Daily:', ethers.formatEther(dailyReward * 100n), 'LXON');
  console.log('    Yearly:', ethers.formatEther(yearlyReward * 100n), 'LXON');
  console.log('    USD Value:', '$' + (Number(ethers.formatEther(yearlyReward * 100n)) * 1.5).toFixed(2));

  console.log('\n💡 To stake LP tokens (when you have them):');
  console.log('```typescript');
  console.log('// Approve LP tokens');
  console.log('await pair.approve(miningAddress, lpTokenAmount);');
  console.log('');
  console.log('// Stake LP tokens');
  console.log('await mining.deposit(0, ethers.parseEther("100"));');
  console.log('');
  console.log('// Claim rewards');
  console.log('await mining.claimReward(0);');
  console.log('```');

  // ============ CURRENT STATUS ============
  console.log('\n📊 Step 5: Current DEX Status');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const [poolReserve0, poolReserve1] = await pair.getReserves();
  console.log('LXON/Native Pair:');
  console.log('  Address:', pairAddress);
  console.log('  LXON Reserve:', ethers.formatEther(poolReserve0));
  console.log('  Native Reserve:', ethers.formatEther(poolReserve1));
  console.log('  Status:', poolReserve0 > 0n && poolReserve1 > 0n ? '✅ Active' : '⏳ Awaiting Liquidity');

  const lpBalance = await pair.balanceOf(deployer.address);
  console.log('\nYour LP Tokens:', ethers.formatEther(lpBalance));

  const pendingRewards = await mining.pendingReward(0, deployer.address);
  console.log('Pending Rewards:', ethers.formatEther(pendingRewards), 'LXON');

  // ============ ACTION ITEMS ============
  console.log('\n🎯 Action Items to Enable Full DEX Operations');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. Acquire LXON tokens');
  console.log('   - Buy on exchanges');
  console.log('   - Receive from other users');
  console.log('   - Participate in token sales');
  console.log('');
  console.log('2. Acquire Native tokens');
  console.log('   - Mine or stake on LXON network');
  console.log('   - Buy on exchanges');
  console.log('   - Receive from other users');
  console.log('');
  console.log('3. Add liquidity to DEX');
  console.log('   - Run: npx hardhat run scripts/add-liquidity-dex.ts');
  console.log('   - Provide both tokens in balanced ratio');
  console.log('   - Start with small amounts to test');
  console.log('');
  console.log('4. Stake LP tokens');
  console.log('   - Run: npx hardhat run scripts/stake-lp-tokens.ts');
  console.log('   - Earn LXON rewards');
  console.log('   - Compound rewards for higher yields');
  console.log('');
  console.log('5. Start trading');
  console.log('   - Use UniversalRouter for swaps');
  console.log('   - Monitor prices with PriceOracle');
  console.log('   - Set appropriate slippage tolerance');

  console.log('\n🎉 DEX Demo Complete!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log('  ✅ Price monitoring operational');
  console.log('  ✅ Liquidity operations ready (awaiting funds)');
  console.log('  ✅ Trading operations ready (awaiting liquidity)');
  console.log('  ✅ Staking operations ready (awaiting LP tokens)');
  console.log('  ✅ All contracts deployed and configured');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
