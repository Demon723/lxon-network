import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Founder Native Balance\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  const deployerAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';

  console.log('Founder:', founderAddress);
  console.log('Deployer:', deployerAddress);
  console.log('');

  // Check native balances
  const founderNative = await ethers.provider.getBalance(founderAddress);
  const deployerNative = await ethers.provider.getBalance(deployerAddress);

  console.log('💰 Native Balances:');
  console.log('  Founder:', ethers.formatEther(founderNative));
  console.log('  Deployer:', ethers.formatEther(deployerNative));
  console.log('');

  if (founderNative < ethers.parseEther('0.01')) {
    console.log('⚠️ Founder has insufficient native tokens for gas');
    console.log('   Sending 0.1 native tokens to founder for gas...');
    console.log('');

    try {
      const [signer] = await ethers.getSigners();
      const sendTx = await signer.sendTransaction({
        to: founderAddress,
        value: ethers.parseEther('0.1')
      });
      console.log('Transaction hash:', sendTx.hash);
      await sendTx.wait();
      console.log('✅ Gas tokens sent to founder');
      console.log('');

      const newFounderNative = await ethers.provider.getBalance(founderAddress);
      console.log('💰 Founder new native balance:', ethers.formatEther(newFounderNative));
    } catch (e: any) {
      console.log('❌ Send failed:', e.message);
    }
  } else {
    console.log('✅ Founder has sufficient native tokens for gas');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
