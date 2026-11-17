import { ethers } from 'hardhat';

async function main() {
  console.log('🎯 Requesting Tokens from Owner...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Deployer:', deployer.address);

  const ownerAddress = '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5';
  const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Owner Address:', ownerAddress);
  console.log('LXON Token:', lxonAddress);
  console.log('Native Token:', nativeTokenAddress);
  console.log('');

  // Check if owner has tokens
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  const ownerLXONBalance = await lxonToken.balanceOf(ownerAddress);
  const ownerNativeBalance = await nativeToken.balanceOf(ownerAddress);

  console.log('📊 Owner Balances:');
  console.log('  LXON:', ethers.formatEther(ownerLXONBalance));
  console.log('  Native:', ethers.formatEther(ownerNativeBalance));
  console.log('');

  // Check if we can act as owner
  console.log('💡 OPTIONS TO ACQUIRE TOKENS:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('OPTION 1: Owner Transfers Tokens (Requires Owner Private Key)');
  console.log('  - Add owner private key to .env as OWNER_PRIVATE_KEY');
  console.log('  - Run: npx hardhat run scripts/transfer-as-owner.ts');
  console.log('');
  console.log('OPTION 2: Owner Mints More Tokens (Requires Mint Authority)');
  console.log('  - Contact owner to mint 100+ LXON to your address');
  console.log('  - Contact owner to transfer 100+ Native tokens');
  console.log('');
  console.log('OPTION 3: Use Block Rewards (Long-term)');
  console.log('  - Wait for block rewards to increase supply');
  console.log('  - May take significant time');
  console.log('');
  console.log('OPTION 4: Purchase on Exchange (If Available)');
  console.log('  - Buy LXON on a cryptocurrency exchange');
  console.log('  - Transfer to your address');
  console.log('');

  // Check if owner has enough to transfer
  const minRequired = ethers.parseEther('1');
  const recommended = ethers.parseEther('100');

  console.log('📋 Owner Has Enough Tokens?');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('LXON:');
  console.log('  Owner Has:', ethers.formatEther(ownerLXONBalance));
  console.log('  Minimum Required:', ethers.formatEther(minRequired));
  console.log('  Recommended:', ethers.formatEther(recommended));
  console.log('  Can Transfer Minimum?', ownerLXONBalance >= minRequired ? '✅ YES' : '❌ NO');
  console.log('  Can Transfer Recommended?', ownerLXONBalance >= recommended ? '✅ YES' : '❌ NO');
  console.log('');
  console.log('Native:');
  console.log('  Owner Has:', ethers.formatEther(ownerNativeBalance));
  console.log('  Minimum Required:', ethers.formatEther(minRequired));
  console.log('  Recommended:', ethers.formatEther(recommended));
  console.log('  Can Transfer Minimum?', ownerNativeBalance >= minRequired ? '✅ YES' : '❌ NO');
  console.log('  Can Transfer Recommended?', ownerNativeBalance >= recommended ? '✅ YES' : '❌ NO');

  console.log('\n🚀 RECOMMENDED ACTION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  if (ownerLXONBalance >= recommended && ownerNativeBalance >= recommended) {
    console.log('✅ Owner has sufficient tokens!');
    console.log('   Contact owner to transfer:');
    console.log('   - 100 LXON to:', deployer.address);
    console.log('   - 100 Native tokens to:', deployer.address);
  } else if (ownerLXONBalance >= minRequired && ownerNativeBalance >= minRequired) {
    console.log('⚠️  Owner has minimum tokens (not recommended)');
    console.log('   Contact owner to transfer:');
    console.log('   - 1 LXON to:', deployer.address);
    console.log('   - 1 Native token to:', deployer.address);
    console.log('   (Warning: Minimum amounts may not be ideal for DEX)');
  } else {
    console.log('❌ Owner does not have sufficient tokens');
    console.log('   Alternative: Request owner to MINT more tokens');
    console.log('   Or wait for block rewards to increase supply');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
