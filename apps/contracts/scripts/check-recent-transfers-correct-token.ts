import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Recent Transfers on Correct Token Contract\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Token:', lxonTokenAddress);
  console.log('Address:', targetAddress);
  console.log('');

  // Scan recent blocks for transfers to this address
  console.log('🔍 Scanning last 100 blocks for transfers...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const transferInterface = new ethers.Interface([
    'event Transfer(address indexed from, address indexed to, uint256 value)'
  ]);

  const currentBlock = await ethers.provider.getBlockNumber();
  let transfers = [];
  const maxBlocks = 100;

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
    console.log(`Found ${transfers.length} transfers to your address:\n`);
    
    for (const tx of transfers) {
      console.log('Block:', tx.block);
      console.log('TX Hash:', tx.hash);
      console.log('From:', tx.from);
      console.log('Amount:', tx.amount, 'LXON');
      console.log('USD Value:', '$' + tx.usd);
      console.log('---');
    }
  } else {
    console.log('❌ No transfers found to your address in last 100 blocks');
    console.log('');
    console.log('💡 This means the 10,000 LXON might be:');
    console.log('1. In a different account');
    console.log('2. On a different network (even if MetaMask says LXON Mainnet)');
    console.log('3. On a different token contract');
    console.log('4. MetaMask showing incorrect/cached data');
  }

  console.log('\n📋 PLEASE CHECK IN METAMASK:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. Go to Settings → Networks');
  console.log('2. Check the RPC URL for LXON Mainnet');
  console.log('3. Provide the RPC URL here');
  console.log('');
  console.log('MetaMask might be using a different RPC than our Hardhat config!');
  console.log('Our RPC: https://rpc.lxon.in');
  console.log('If MetaMask uses a different RPC, balances will differ.');
  console.log('');

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
