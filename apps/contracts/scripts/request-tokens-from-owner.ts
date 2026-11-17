import { ethers } from 'hardhat';

async function main() {
  console.log('💸 Requesting Tokens from Owner Address...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Deployer Account:', deployer.address);

  // Owner address (from earlier check)
  const ownerAddress = '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5';
  console.log('Owner Address:', ownerAddress);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check owner balances
  const ownerLXON = await lxonToken.balanceOf(ownerAddress);
  const ownerNative = await nativeToken.balanceOf(ownerAddress);
  
  console.log('\nOwner Balances:');
  console.log('LXON:', ethers.formatEther(ownerLXON));
  console.log('Native:', ethers.formatEther(ownerNative));

  if (ownerLXON === 0n && ownerNative === 0n) {
    console.log('\n❌ Owner has no tokens either.');
    console.log('💡 The tokens may need to be minted first.');
    process.exit(1);
  }

  console.log('\n💡 To transfer tokens from owner, you need:');
  console.log('1. Owner to approve transfer to deployer');
  console.log('2. Or owner to directly transfer tokens');
  console.log('3. Or use owner private key to execute transfer');

  console.log('\n📝 Instructions for owner:');
  console.log('```bash');
  console.log('# Using owner private key (if available)');
  console.log('OWNER_PRIVATE_KEY=<owner_private_key> \\');
  console.log('npx hardhat run scripts/transfer-as-owner.ts --network lxonMainnet');
  console.log('```');

  // For now, let's just show what we would transfer
  const transferAmountLXON = ownerLXON > ethers.parseEther('100') ? ethers.parseEther('100') : ownerLXON / 10n;
  const transferAmountNative = ownerNative > ethers.parseEther('100') ? ethers.parseEther('100') : ownerNative / 10n;

  console.log('\n💡 Suggested Transfer Amounts:');
  console.log('LXON:', ethers.formatEther(transferAmountLXON));
  console.log('Native:', ethers.formatEther(transferAmountNative));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
