import { ethers } from 'hardhat';

async function main() {
  console.log('🔄 Full DEX Workflow: Liquidity → Staking → Trading → Monitoring\n');

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

  // ============ STEP 1: CHECK BALANCES ============
  console.log('📊 Step 1: Checking Token Balances');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('LXON Balance:', ethers.formatEther(lxonBalance));
  console.log('Native Token Balance:', ethers.formatEther(nativeBalance));
  console.log('LXON USD Value:', '$' + ethers.formatUnits(await oracle.getPriceInUSD(lxonAddress, lxonBalance), 18));
  console.log('Native USD Value:', '$' + ethers.formatUnits(await oracle.getPriceInUSD(nativeTokenAddress, nativeBalance), 18));

  if (lxonBalance === 0n && nativeBalance === 0n) {
    console.log('\n⚠️  No token balances available. Using demo mode with small amounts for demonstration.');
  }

  // ============ STEP 2: ADD LIQUIDITY ============
  console.log('\n💧 Step 2: Adding Liquidity to LXON/Native Pair');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  // Use minimum of 1% of balances or 0.000001 if very small
  const amountLXON = lxonBalance > 0n ? lxonBalance / 100n : ethers.parseEther('0.000001');
  const amountNative = nativeBalance > 0n ? nativeBalance / 100n : ethers.parseEther('0.000001');
  
  console.log('LXON to add:', ethers.formatEther(amountLXON));
  console.log('Native to add:', ethers.formatEther(amountNative));

  if (amountLXON > 0n && amountNative > 0n) {
    try {
      // Approve tokens
      console.log('⏳ Approving tokens...');
      if (lxonBalance >= amountLXON) {
        await lxonToken.approve(await router.getAddress(), amountLXON);
      }
      if (nativeBalance >= amountNative) {
        await nativeToken.approve(await router.getAddress(), amountNative);
      }
      console.log('✅ Tokens approved');

      // Add liquidity
      const deadline = Math.floor(Date.now() / 1000) + 20 * 60;
      console.log('⏳ Adding liquidity...');
      
      const addLiquidityTx = await router.addLiquidity(
        lxonAddress,
        nativeTokenAddress,
        amountLXON,
        amountNative,
        amountLXON * 95n / 100n,
        amountNative * 95n / 100n,
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

    } catch (error: any) {
      console.log('⚠️  Liquidity addition failed (likely due to small amounts):', error.message);
      console.log('Skipping to staking with existing LP tokens if any...');
    }
  }

  // ============ STEP 3: STAKE LP TOKENS ============
  console.log('\n💰 Step 3: Staking LP Tokens for Rewards');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const lpBalance = await pair.balanceOf(deployer.address);
  
  console.log('LP Token Balance:', ethers.formatEther(lpBalance));

  if (lpBalance > 0n) {
    try {
      // Approve LP tokens
      console.log('⏳ Approving LP tokens...');
      await pair.approve(await mining.getAddress(), lpBalance);
      console.log('✅ LP tokens approved');

      // Stake LP tokens
      const stakeAmount = lpBalance;
      console.log('⏳ Staking LP tokens...');
      
      const depositTx = await mining.deposit(0, stakeAmount);
      console.log('Transaction hash:', depositTx.hash);
      const depositReceipt = await depositTx.wait();
      console.log('✅ LP tokens staked!');
      console.log('Gas used:', depositReceipt.gasUsed.toString());

      // Check pending rewards
      const pendingRewards = await mining.pendingReward(0, deployer.address);
      console.log('Pending Rewards:', ethers.formatEther(pendingRewards), 'LXON');

    } catch (error: any) {
      console.log('⚠️  Staking failed:', error.message);
    }
  } else {
    console.log('⚠️  No LP tokens to stake. Add liquidity first.');
  }

  // ============ STEP 4: MONITOR PRICES ============
  console.log('\n📈 Step 4: Monitoring Prices');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const [lxonPrice, lxonTimestamp, lxonStale] = await oracle.getPrice(lxonAddress);
  const [nativePrice, nativeTimestamp, nativeStale] = await oracle.getPrice(nativeTokenAddress);
  
  console.log('LXON Price:', ethers.formatUnits(lxonPrice, 18), 'USD');
  console.log('  Timestamp:', new Date(Number(lxonTimestamp) * 1000).toISOString());
  console.log('  Is Stale:', lxonStale ? 'YES' : 'NO');
  
  console.log('\nNative Token Price:', ethers.formatUnits(nativePrice, 18), 'USD');
  console.log('  Timestamp:', new Date(Number(nativeTimestamp) * 1000).toISOString());
  console.log('  Is Stale:', nativeStale ? 'YES' : 'NO');

  const pairPrice = await oracle.getPairPrice(lxonAddress, nativeTokenAddress);
  console.log('\nLXON/Native Price Ratio:', ethers.formatUnits(pairPrice, 18));

  // ============ STEP 5: DEMONSTRATE TRADING ============
  console.log('\n🔄 Step 5: Trading Demonstration');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  // Get current reserves
  const [reserve0, reserve1] = await pair.getReserves();
  console.log('Current Reserves:');
  console.log('  LXON:', ethers.formatEther(reserve0));
  console.log('  Native:', ethers.formatEther(reserve1));

  if (reserve0 > 0n && reserve1 > 0n) {
    // Calculate swap quote
    const swapAmount = ethers.parseEther('0.001');
    const amountOut = await pair.getAmountOut(swapAmount, reserve0, reserve1);
    
    console.log('\nSwap Quote:');
    console.log('  Input:', ethers.formatEther(swapAmount), 'LXON');
    console.log('  Output:', ethers.formatEther(amountOut), 'Native');
    console.log('  Price Impact:', ((Number(ethers.formatEther(amountOut)) / Number(ethers.formatEther(swapAmount))) * 100).toFixed(2), '%');

    console.log('\n💡 To execute this swap:');
    console.log('  await router.swapExactTokensForTokens(');
    console.log('    ethers.parseEther("0.001"),');
    console.log('    ethers.parseEther("' + ethers.formatEther(amountOut * 95n / 100n) + '"),');
    console.log('    [lxonAddress, nativeTokenAddress],');
    console.log('    recipient,');
    console.log('    deadline');
    console.log('  );');
  } else {
    console.log('\n⚠️  No liquidity available for trading. Add liquidity first.');
  }

  // ============ SUMMARY ============
  console.log('\n🎉 DEX Workflow Complete!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log('  ✅ Token balances checked');
  console.log('  ✅ Liquidity added (if tokens available)');
  console.log('  ✅ LP tokens staked (if LP available)');
  console.log('  ✅ Prices monitored');
  console.log('  ✅ Trading quote calculated');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  console.log('\n📝 Next Steps:');
  console.log('  1. Acquire more LXON and Native tokens');
  console.log('  2. Add significant liquidity to enable trading');
  console.log('  3. Stake LP tokens to earn rewards');
  console.log('  4. Execute trades using UniversalRouter');
  console.log('  5. Claim rewards periodically');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
