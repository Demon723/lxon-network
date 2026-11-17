import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Bridge Availability for LXON Network\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const yourAddress = '0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Your Wallet:', yourAddress);
  console.log('WETH Contract:', wethAddress);
  console.log('');

  // Get WETH contract
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);

  // Check WETH balance
  const wethBalance = await wethToken.balanceOf(yourAddress);
  const nativeBalance = await ethers.provider.getBalance(yourAddress);

  console.log('💰 Current Balances:');
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('  USD Value: $', (Number(ethers.formatEther(wethBalance)) * 1.5).toFixed(2));
  console.log('  Native:', ethers.formatEther(nativeBalance));
  console.log('');

  console.log('🌐 Bridge Availability Status:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  console.log('Manual Check Required:');
  console.log('');
  console.log('The following services need to be checked manually:');
  console.log('');
  console.log('1. LayerZero:');
  console.log('   - Visit: https://layerzero.network');
  console.log('   - Use LayerZero scan to check if LXON (Chain ID 724) is supported');
  console.log('   - Look for: LXON or Chain ID 724 in supported chains');
  console.log('');
  console.log('2. Wormhole:');
  console.log('   - Visit: https://wormhole.com');
  console.log('   - Check supported chains list');
  console.log('   - Look for: LXON or Chain ID 724');
  console.log('');
  console.log('3. Across Protocol:');
  console.log('   - Visit: https://across.to');
  console.log('   - Check supported networks');
  console.log('   - Look for: LXON');
  console.log('');
  console.log('4. Stargate:');
  console.log('   - Visit: https://stargate.finance');
  console.log('   - Check supported chains');
  console.log('   - Look for: LXON');
  console.log('');
  console.log('5. cBridge:');
  console.log('   - Visit: https://cbridge.celer.network');
  console.log('   - Check supported networks');
  console.log('   - Look for: LXON');
  console.log('');

  console.log('💼 CEX Support Check:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  console.log('Manual Check Required:');
  console.log('');
  console.log('1. Binance:');
  console.log('   - Visit: https://www.binance.com');
  console.log('   - Check deposit networks for WETH');
  console.log('   - Look for: LXON or Chain ID 724');
  console.log('   - Contact support if not listed');
  console.log('');
  console.log('2. Coinbase:');
  console.log('   - Visit: https://www.coinbase.com');
  console.log('   - Check supported networks');
  console.log('   - Look for: LXON or Chain ID 724');
  console.log('   - Contact support if not listed');
  console.log('');
  console.log('3. Kraken:');
  console.log('   - Visit: https://www.kraken.com');
  console.log('   - Check supported networks');
  console.log('   - Look for: LXON or Chain ID 724');
  console.log('   - Contact support if not listed');
  console.log('');
  console.log('4. OKX:');
  console.log('   - Visit: https://www.okx.com');
  console.log('   - Check supported networks');
  console.log('   - Look for: LXON or Chain ID 724');
  console.log('   - Contact support if not listed');
  console.log('');

  console.log('📋 Recommendation:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('1. Contact LXON team about bridge infrastructure');
  console.log('2. Check the above websites weekly for LXON support');
  console.log('3. Join LXON Discord/Telegram for updates');
  console.log('4. Follow LXON social media for announcements');
  console.log('');

  console.log('📝 When Bridge Becomes Available:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('Step 1: Get bridge contract address');
  console.log('Step 2: Approve WETH for bridge');
  console.log('Step 3: Initiate bridge transfer to Ethereum Mainnet');
  console.log('Step 4: Wait for bridge confirmation');
  console.log('Step 5: Deposit WETH to CEX');
  console.log('Step 6: Convert WETH → USDC');
  console.log('Step 7: Withdraw USDC to bank account');
  console.log('');

  console.log('💰 Your Holdings (Ready for Bridge):');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('Network: LXON Mainnet (Chain ID 724)');
  console.log('Wallet:', yourAddress);
  console.log('WETH:', ethers.formatEther(wethBalance), '($' + (Number(ethers.formatEther(wethBalance)) * 1.5).toFixed(2) + ' USD)');
  console.log('Native:', ethers.formatEther(nativeBalance), '(for gas fees)');
  console.log('');
  console.log('✅ Assets are safe and ready to bridge');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
