import { ethers } from 'hardhat';

async function main() {
  console.log('💸 Transferring Tokens as Owner...\n');

  // Check if owner private key is provided
  const ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (!ownerPrivateKey) {
    console.log('❌ OWNER_PRIVATE_KEY not set in environment');
    console.log('💡 Please set it with:');
    console.log('   export OWNER_PRIVATE_KEY=<owner_private_key>');
    console.log('   or add to .env file');
    process.exit(1);
  }

  // Create owner wallet
  const ownerWallet = new ethers.Wallet(ownerPrivateKey);
  const provider = ethers.provider;
  const ownerSigner = ownerWallet.connect(provider);

  console.log('Owner Account:', ownerSigner.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress, ownerSigner);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress, ownerSigner);

  // Check owner balances
  const ownerLXON = await lxonToken.balanceOf(ownerSigner.address);
  const ownerNative = await nativeToken.balanceOf(ownerSigner.address);
  
  console.log('Owner Balances:');
  console.log('LXON:', ethers.formatEther(ownerLXON));
  console.log('Native:', ethers.formatEther(ownerNative));

  // Deployer address
  const deployerAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  console.log('\nTransfer to:', deployerAddress);

  // Transfer amounts (10% of owner's balance)
  const transferLXON = ownerLXON / 10n;
  const transferNative = ownerNative / 10n;

  console.log('\nTransfer Amounts:');
  console.log('LXON:', ethers.formatEther(transferLXON));
  console.log('Native:', ethers.formatEther(transferNative));

  if (transferLXON > 0n) {
    console.log('\n⏳ Transferring LXON...');
    const tx = await lxonToken.transfer(deployerAddress, transferLXON);
    console.log('Transaction hash:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ LXON transferred!');
  }

  if (transferNative > 0n) {
    console.log('\n⏳ Transferring Native...');
    const tx = await nativeToken.transfer(deployerAddress, transferNative);
    console.log('Transaction hash:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ Native transferred!');
  }

  console.log('\n🎉 Transfer complete!');
  console.log('💡 Now run the DEX workflow scripts with the new balances.');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
