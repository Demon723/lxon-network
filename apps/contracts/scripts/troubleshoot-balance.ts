import { ethers } from 'hardhat';

async function main() {
  console.log('🔧 Troubleshooting Balance Update Issue...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Check current block
  const currentBlock = await ethers.provider.getBlockNumber();
  console.log('Current Block:', currentBlock);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check current balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('\n📊 Current Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native:', ethers.formatEther(nativeBalance));

  // Check total supply
  const totalSupply = await lxonToken.totalSupply();
  console.log('\nLXON Total Supply:', ethers.formatEther(totalSupply));

  // Check last 50 blocks for transfers to our address
  console.log('\n🔍 Scanning last 50 blocks for transfers to your address...');
  
  let foundTransfers = [];
  const transferInterface = new ethers.Interface([
    'event Transfer(address indexed from, address indexed to, uint256 value)'
  ]);

  for (let i = 0; i < 50; i++) {
    const checkBlock = currentBlock - i;
    if (checkBlock < 0) break;
    
    try {
      const block = await ethers.provider.getBlock(checkBlock, true);
      if (block && block.transactions) {
        for (const tx of block.transactions) {
          if (tx.to && tx.to.toLowerCase() === lxonAddress.toLowerCase()) {
            try {
              const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
              if (receipt) {
                for (const log of receipt.logs) {
                  if (log.address.toLowerCase() === lxonAddress.toLowerCase()) {
                    try {
                      const parsed = transferInterface.parseLog(log);
                      if (parsed.args.to.toLowerCase() === deployer.address.toLowerCase()) {
                        foundTransfers.push({
                          block: checkBlock,
                          hash: tx.hash,
                          from: parsed.args.from,
                          amount: ethers.formatEther(parsed.args.value),
                          usd: (Number(ethers.formatEther(parsed.args.value)) * 1.5).toFixed(2)
                        });
                      }
                    } catch (e) {
                      // Skip logs that can't be parsed
                    }
                  }
                }
              }
            } catch (e) {
              // Skip if receipt not available
            }
          }
        }
      }
    } catch (e) {
      // Skip if block not available
    }
  }

  if (foundTransfers.length > 0) {
    console.log('\n✅ Found recent transfers to your address:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    for (const tx of foundTransfers) {
      console.log(`Block ${tx.block}:`);
      console.log('  Hash:', tx.hash);
      console.log('  From:', tx.from);
      console.log('  Amount:', tx.amount, 'LXON');
      console.log('  USD Value: $' + tx.usd);
    }
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  } else {
    console.log('\n❌ No recent transfers found to your address in last 50 blocks');
  }

  // Check if there might be multiple LXON token contracts
  console.log('\n🔍 Checking for other potential LXON token contracts...');
  console.log('Current LXON address:', lxonAddress);
  console.log('💡 Common alternative addresses to check:');
  console.log('  - Wrapped LXON (if exists)');
  console.log('  - Different deployment addresses');
  console.log('  - Bridge contracts');

  // Check network RPC
  const network = await ethers.provider.getNetwork();
  console.log('\n🌐 Network Info:');
  console.log('  Chain ID:', network.chainId);
  console.log('  Network Name:', network.name);
  console.log('  Expected: 724 (LXON Mainnet)');

  if (Number(network.chainId) !== 724) {
    console.log('\n⚠️  WARNING: Wrong network!');
    console.log('   You are connected to chain ID:', network.chainId);
    console.log('   Expected chain ID: 724 (LXON Mainnet)');
    console.log('   This might explain why the balance isn\'t updating');
  }

  // Diagnosis
  console.log('\n🔍 Diagnosis:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  if (foundTransfers.length === 0) {
    console.log('❌ No transfers found - Possible causes:');
    console.log('   1. Transaction sent to wrong address');
    console.log('   2. Transaction sent on wrong network');
    console.log('   3. Transaction still pending (not in recent blocks)');
    console.log('   4. Transaction sent to different token contract');
  } else {
    console.log('✅ Transfers found but balance low - Possible causes:');
    console.log('   1. Sum of transfers is still small');
    console.log('   2. Some transfers failed');
    console.log('   3. Different token contract address');
  }
  
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  console.log('\n💡 Recommended Actions:');
  console.log('1. Verify transaction hash from MetaMask');
  console.log('2. Check recipient address in MetaMask');
  console.log('3. Verify network in MetaMask (should be LXON Mainnet)');
  console.log('4. Check if tokens are locked or require approval');
  console.log('5. Try refreshing or resyncing MetaMask');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
