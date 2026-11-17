import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Weekly Bridge Availability Check\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  console.log('Date:', new Date().toISOString());
  console.log('');

  const yourAddress = '0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Your Wallet:', yourAddress);
  console.log('');

  // Check WETH balance
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);
  const wethBalance = await wethToken.balanceOf(yourAddress);
  const nativeBalance = await ethers.provider.getBalance(yourAddress);

  console.log('💰 Current Holdings:');
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('  USD Value: $', (Number(ethers.formatEther(wethBalance)) * 1.5).toFixed(2));
  console.log('  Native (for gas):', ethers.formatEther(nativeBalance));
  console.log('');

  console.log('🌐 Manual Bridge Check List:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('✅ Task 1: Check Third-Party Bridges');
  console.log('   Visit these websites and search for "LXON" or "Chain ID 724":');
  console.log('   - LayerZero: https://layerzero.network');
  console.log('   - Wormhole: https://wormhole.com');
  console.log('   - Across: https://across.to');
  console.log('   - Stargate: https://stargate.finance');
  console.log('   - cBridge: https://cbridge.celer.network');
  console.log('');
  console.log('   What to look for:');
  console.log('   - LXON in supported chains list');
  console.log('   - Chain ID 724 in supported chains');
  console.log('   - Bridge from LXON to Ethereum');
  console.log('');

  console.log('✅ Task 2: Check CEX Support');
  console.log('   Visit these exchanges and check deposit networks:');
  console.log('   - Binance: https://www.binance.com');
  console.log('   - Coinbase: https://www.coinbase.com');
  console.log('   - Kraken: https://www.kraken.com');
  console.log('   - OKX: https://www.okx.com');
  console.log('');
  console.log('   What to look for:');
  console.log('   - LXON network in deposit options');
  console.log('   - WETH deposit on LXON network');
  console.log('   - Contact support if not listed');
  console.log('');

  console.log('✅ Task 3: Check LXON Announcements');
  console.log('   Check these for bridge updates:');
  console.log('   - LXON official website');
  console.log('   - LXON Discord server');
  console.log('   - LXON Telegram group');
  console.log('   - LXON Twitter/X');
  console.log('   - LXON blog/news');
  console.log('');

  console.log('✅ Task 4: Check Deployed Bridge Status');
  console.log('   Bridge on LXON: 0x38e0Fc3E0E32dBD89984DB12eF4B5349D420b30D');
  console.log('   Check if:');
  console.log('   - Peer bridge registered on Ethereum');
  console.log('   - Validators added');
  console.log('   - Bridge activated');
  console.log('');

  console.log('📋 Weekly Checklist:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('Week of:', new Date().toLocaleDateString());
  console.log('');
  console.log('[ ] Checked LayerZero for LXON support');
  console.log('[ ] Checked Wormhole for LXON support');
  console.log('[ ] Checked Across for LXON support');
  console.log('[ ] Checked Stargate for LXON support');
  console.log('[ ] Checked cBridge for LXON support');
  console.log('[ ] Checked Binance for LXON network');
  console.log('[ ] Checked Coinbase for LXON network');
  console.log('[ ] Checked Kraken for LXON network');
  console.log('[ ] Checked OKX for LXON network');
  console.log('[ ] Checked LXON Discord for updates');
  console.log('[ ] Checked LXON Twitter for updates');
  console.log('[ ] Checked LXON blog for updates');
  console.log('[ ] Checked deployed bridge status');
  console.log('');

  console.log('📝 Notes:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('Record any findings here:');
  console.log('- Bridge found: _________________');
  console.log('- CEX support: _________________');
  console.log('- LXON announcements: _________________');
  console.log('- Other: _________________');
  console.log('');

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('💡 Reminder: Run this script weekly to monitor progress');
  console.log('💡 When bridge becomes available, contact me to execute');
  console.log('💡 Your WETH is safe and ready to bridge');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
