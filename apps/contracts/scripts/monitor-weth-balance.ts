import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Monitoring WETH Balance on LXON Network\n');
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

  console.log('📊 WETH Details:');
  console.log('  Contract:', wethAddress);
  console.log('  Decimals: 18');
  console.log('  Network: LXON Mainnet (Chain ID 724)');
  console.log('');

  console.log('🎯 Ready for Bridge:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('When bridge information is available:');
  console.log('1. Use bridge service to transfer WETH to Ethereum Mainnet');
  console.log('2. Deposit WETH to CEX (Binance, Coinbase, Kraken)');
  console.log('3. Convert WETH → USDC');
  console.log('4. Withdraw USDC to bank account');
  console.log('');

  console.log('💡 Reminder:');
  console.log('  - Contact LXON team about bridge options');
  console.log('  - Check third-party bridges (LayerZero, Wormhole)');
  console.log('  - Ask CEXs about LXON network support');
  console.log('  - Use OTC desk if needed');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
