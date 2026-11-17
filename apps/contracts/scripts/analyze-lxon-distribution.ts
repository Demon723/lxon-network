import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Analyzing LXON Token Distribution...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token address
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);

  // Get total supply
  const totalSupply = await lxonToken.totalSupply();
  console.log('LXON Total Supply:', ethers.formatEther(totalSupply));
  console.log('USD Value at $1.50/LXON:', '$' + (Number(ethers.formatEther(totalSupply)) * 1.5).toFixed(2));

  // Check known addresses
  const knownAddresses = [
    '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5', // Owner
    '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27', // Deployer
    '0x18222bab07224d4Dad6c1295Aa53db3834D9bB90', // Multi-sig
    '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27', // Deployer (duplicate check)
  ];

  console.log('\n📊 Known Address Balances:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  for (const addr of knownAddresses) {
    const balance = await lxonToken.balanceOf(addr);
    const percentage = (Number(balance) * 100 / Number(totalSupply)).toFixed(4);
    
    if (balance > 0n) {
      console.log(`${addr}:`);
      console.log('  Balance:', ethers.formatEther(balance), 'LXON');
      console.log('  USD Value:', '$' + (Number(ethers.formatEther(balance)) * 1.5).toFixed(2));
      console.log('  % of Supply:', percentage + '%');
    }
  }

  // Scan recent blocks for transfers
  console.log('\n🔍 Scanning recent blocks for LXON transfers...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const currentBlock = await ethers.provider.getBlockNumber();
  const transferInterface = new ethers.Interface([
    'event Transfer(address indexed from, address indexed to, uint256 value)'
  ]);

  let transfers = [];
  const maxBlocks = 100;

  for (let i = 0; i < maxBlocks; i++) {
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
                      transfers.push({
                        block: checkBlock,
                        hash: tx.hash,
                        from: parsed.args.from,
                        to: parsed.args.to,
                        amount: ethers.formatEther(parsed.args.value),
                        usd: (Number(ethers.formatEther(parsed.args.value)) * 1.5).toFixed(2)
                      });
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

  if (transfers.length > 0) {
    console.log(`Found ${transfers.length} transfers in last ${maxBlocks} blocks:\n`);
    
    // Group by recipient
    const byRecipient = {};
    for (const tx of transfers) {
      if (!byRecipient[tx.to]) {
        byRecipient[tx.to] = { amount: 0n, count: 0 };
      }
      byRecipient[tx.to].amount += ethers.parseEther(tx.amount);
      byRecipient[tx.to].count += 1;
    }

    console.log('📥 Recipients of recent transfers:');
    for (const [recipient, data] of Object.entries(byRecipient)) {
      const percentage = (Number(data.amount) * 100 / Number(totalSupply)).toFixed(4);
      console.log(`  ${recipient}:`);
      console.log('    Total Received:', ethers.formatEther(data.amount), 'LXON');
      console.log('    Transfer Count:', data.count);
      console.log('    % of Supply:', percentage + '%');
    }
  } else {
    console.log('No transfers found in last 100 blocks');
  }

  // Find addresses with significant balances
  console.log('\n🔍 Looking for addresses with significant balances...');
  console.log('💡 This would require scanning the entire blockchain, which is very slow.');
  console.log('   Instead, checking common holder addresses...');

  // Check deployer address balance again
  const deployerBalance = await lxonToken.balanceOf(deployer.address);
  console.log('\n📊 Your Current Balance:', ethers.formatEther(deployerBalance), 'LXON');
  console.log('USD Value:', '$' + (Number(ethers.formatEther(deployerBalance)) * 1.5).toFixed(2));

  console.log('\n💡 To find where LXON is going:');
  console.log('1. Check recent transactions (done above)');
  console.log('2. Look at top holders (requires blockchain explorer)');
  console.log('3. Check token distribution in other tools');
  console.log('4. Review owner address (holds most tokens)');

  console.log('\n🎯 Summary:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Total Supply:', ethers.formatEther(totalSupply), 'LXON');
  console.log('Your Balance:', ethers.formatEther(deployerBalance), 'LXON');
  console.log('Percentage:', (Number(deployerBalance) * 100 / Number(totalSupply)).toFixed(6) + '%');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
