import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Recent Transactions and Token Transfers...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check current block
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log('Current block:', blockNumber);

  // Check recent blocks for transfers
  console.log('\n🔍 Checking recent blocks for token transfers...');
  
  // Check last 10 blocks
  for (let i = 0; i < 10; i++) {
    const checkBlock = blockNumber - i;
    if (checkBlock < 0) break;
    
    try {
      const block = await ethers.provider.getBlock(checkBlock, true);
      if (block && block.transactions) {
        for (const tx of block.transactions) {
          if (tx.to && (tx.to.toLowerCase() === lxonAddress.toLowerCase() || tx.to.toLowerCase() === nativeTokenAddress.toLowerCase())) {
            console.log(`\nBlock ${checkBlock}:`);
            console.log('  Hash:', tx.hash);
            console.log('  From:', tx.from);
            console.log('  To:', tx.to);
          }
        }
      }
    } catch (e) {
      // Skip if block not available
    }
  }

  // Check if tokens were sent to a different address
  console.log('\n💡 Did you send tokens to a different address?');
  console.log('   Please verify the recipient address matches:', deployer.address);
  
  // Check common addresses
  const addressesToCheck = [
    '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5', // Owner
    '0x18222bab07224d4Dad6c1295Aa53db3834D9bB90', // Multi-sig
  ];
  
  console.log('\n🔍 Checking if tokens sent to other addresses...');
  for (const addr of addressesToCheck) {
    const lxonBal = await lxonToken.balanceOf(addr);
    const nativeBal = await nativeToken.balanceOf(addr);
    
    if (lxonBal > ethers.parseEther('0.1') || nativeBal > ethers.parseEther('0.1')) {
      console.log(`\n${addr}:`);
      console.log('  LXON:', ethers.formatEther(lxonBal));
      console.log('  Native:', ethers.formatEther(nativeBal));
    }
  }

  // Current balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('\n📊 Your Current Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native:', ethers.formatEther(nativeBalance));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
