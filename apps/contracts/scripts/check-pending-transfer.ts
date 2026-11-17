import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking for Recent Transfers to Your Address\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Target Address:', targetAddress);
  console.log('Token:', lxonTokenAddress);
  console.log('');

  // Scan recent blocks for transfers
  console.log('🔍 Scanning last 50 blocks for transfers...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const transferInterface = new ethers.Interface([
    'event Transfer(address indexed from, address indexed to, uint256 value)'
  ]);

  const currentBlock = await ethers.provider.getBlockNumber();
  let transfers = [];
  const maxBlocks = 50;

  for (let i = 0; i < maxBlocks; i++) {
    const checkBlock = currentBlock - i;
    if (checkBlock < 0) break;
    
    try {
      const block = await ethers.provider.getBlock(checkBlock, true);
      if (block && block.transactions) {
        for (const tx of block.transactions) {
          if (tx.to && tx.to.toLowerCase() === lxonTokenAddress.toLowerCase()) {
            try {
              const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
              if (receipt) {
                for (const log of receipt.logs) {
                  if (log.address.toLowerCase() === lxonTokenAddress.toLowerCase()) {
                    try {
                      const parsed = transferInterface.parseLog(log);
                      if (parsed.args.to.toLowerCase() === targetAddress.toLowerCase()) {
                        transfers.push({
                          block: checkBlock,
                          hash: tx.hash,
                          from: parsed.args.from,
                          to: parsed.args.to,
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

  if (transfers.length > 0) {
    console.log(`Found ${transfers.length} transfers:\n`);
    
    for (const tx of transfers) {
      console.log('Block:', tx.block);
      console.log('TX Hash:', tx.hash);
      console.log('From:', tx.from);
      console.log('Amount:', tx.amount, 'LXON');
      console.log('USD Value:', '$' + tx.usd);
      console.log('---');
    }
  } else {
    console.log('❌ No transfers found in last 50 blocks');
  }

  console.log('\n📊 Current Block:', currentBlock);
  console.log('📊 Current Balance:', (await (await ethers.getContractAt('IERC20', lxonTokenAddress)).balanceOf(targetAddress)).toString());
  console.log('');

  console.log('💡 If you just transferred, it might be:');
  console.log('1. Still pending (in mempool)');
  console.log('2. In a block higher than current block + 50');
  console.log('3. Sent to a different address');
  console.log('4. Not confirmed yet');
  console.log('');
  console.log('Please provide the transaction hash of the transfer you just made');
  console.log('so I can check its status and confirm the recipient address.');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
