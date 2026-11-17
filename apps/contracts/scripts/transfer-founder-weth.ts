import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Transfer WETH from Founder to Your Wallet\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // Read founder private key from environment
  const founderPrivateKey = process.env.FOUNDER_PRIVATE_KEY;
  
  if (!founderPrivateKey) {
    console.log('❌ FOUNDER_PRIVATE_KEY not found in .env file');
    console.log('');
    console.log('Please add the founder private key to .env:');
    console.log('FOUNDER_PRIVATE_KEY=0x...');
    console.log('');
    console.log('Founder Address: 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3');
    return;
  }

  // Your wallet address (update this to your actual address)
  const yourAddress = process.env.YOUR_WALLET_ADDRESS || '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Founder Address:', founderAddress);
  console.log('Your Address:', yourAddress);
  console.log('WETH Contract:', wethAddress);
  console.log('');

  // Create wallet from founder private key
  const founderWallet = new ethers.Wallet(founderPrivateKey, ethers.provider);

  // Verify the wallet matches the founder address
  if (founderWallet.address.toLowerCase() !== founderAddress.toLowerCase()) {
    console.log('❌ Private key does not match founder address');
    console.log('   Expected:', founderAddress);
    console.log('   Got:', founderWallet.address);
    return;
  }

  console.log('✅ Founder wallet verified');
  console.log('');

  // Get WETH contract
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);

  // Check founder's WETH balance
  const founderBalance = await wethToken.balanceOf(founderAddress);
  console.log('💰 Founder WETH Balance:', ethers.formatEther(founderBalance));
  console.log('USD Value: $', (Number(ethers.formatEther(founderBalance)) * 1.5).toFixed(2));
  console.log('');

  if (founderBalance === 0n) {
    console.log('❌ No WETH to transfer');
    return;
  }

  // Ask for confirmation
  console.log('⚠️  This will transfer ALL WETH from founder to your address');
  console.log('   Amount:', ethers.formatEther(founderBalance), 'WETH');
  console.log('   To:', yourAddress);
  console.log('');
  console.log('Press Ctrl+C to cancel, or wait 5 seconds to proceed...');
  
  await new Promise(resolve => setTimeout(resolve, 5000));
  console.log('');

  // Transfer WETH
  console.log('⏳ Transferring WETH...');
  try {
    const transferTx = await wethToken.connect(founderWallet).transfer(yourAddress, founderBalance);
    console.log('Transaction hash:', transferTx.hash);
    await transferTx.wait();
    console.log('✅ Transfer complete');
    console.log('');

    // Check new balances
    const newFounderBalance = await wethToken.balanceOf(founderAddress);
    const yourBalance = await wethToken.balanceOf(yourAddress);
    
    console.log('💰 New Balances:');
    console.log('  Founder:', ethers.formatEther(newFounderBalance), 'WETH');
    console.log('  Your Wallet:', ethers.formatEther(yourBalance), 'WETH');
    console.log('');

    console.log('🎉 Transfer successful!');
    console.log('');
    console.log('Next steps:');
    console.log('1. Send WETH to your CEX deposit address');
    console.log('2. Convert WETH → USDC on CEX');
    console.log('3. Withdraw USDC to bank account');

  } catch (e: any) {
    console.log('❌ Transfer failed:', e.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
