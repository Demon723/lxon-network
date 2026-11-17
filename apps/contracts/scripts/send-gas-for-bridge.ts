import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Sending Gas Tokens to Your Wallet for Bridge\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const yourAddress = '0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b';

  console.log('Deployer:', deployer.address);
  console.log('Your Wallet:', yourAddress);
  console.log('');

  // Check current balances
  const yourNative = await ethers.provider.getBalance(yourAddress);
  const deployerNative = await ethers.provider.getBalance(deployer.address);

  console.log('💰 Current Native Balances:');
  console.log('  Your Wallet:', ethers.formatEther(yourNative));
  console.log('  Deployer:', ethers.formatEther(deployerNative));
  console.log('');

  // Send 0.5 native tokens for gas
  const gasToSend = ethers.parseEther('0.5');

  if (yourNative < ethers.parseEther('0.1')) {
    console.log('⏳ Sending 0.5 native tokens for bridge gas...');
    try {
      const sendTx = await deployer.sendTransaction({
        to: yourAddress,
        value: gasToSend
      });
      console.log('Transaction hash:', sendTx.hash);
      await sendTx.wait();
      console.log('✅ Gas tokens sent');
      console.log('');

      const newYourNative = await ethers.provider.getBalance(yourAddress);
      console.log('💰 Your new native balance:', ethers.formatEther(newYourNative));
      console.log('');

      console.log('✅ Ready for bridge operations');
      console.log('');
      console.log('When bridge info is available, you will have:');
      console.log('  - WETH: 2,326.24 ($3,489 USD)');
      console.log('  - Native: 0.5 (for gas fees)');
      console.log('');
      console.log('This will allow you to:');
      console.log('  - Approve WETH for bridge');
      console.log('  - Initiate bridge transfer');
      console.log('  - Pay bridge fees');

    } catch (e: any) {
      console.log('❌ Send failed:', e.message);
    }
  } else {
    console.log('✅ You already have sufficient native tokens for gas');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
