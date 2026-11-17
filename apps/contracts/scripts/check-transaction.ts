import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Transaction...\n');

  const txHash = '0x86607c374e184954fc6bcd2ed33a51a0a40d9026c0084339b8df0bc8e3c7d478';
  console.log('Transaction ID:', txHash);

  try {
    console.log('\n⏳ Fetching transaction...');
    const tx = await ethers.provider.getTransaction(txHash);
    
    console.log('✅ Transaction found!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('Transaction Details:');
    console.log('  From:', tx.from);
    console.log('  To:', tx.to);
    console.log('  Value:', ethers.formatEther(tx.value), 'ETH');
    console.log('  Gas Limit:', tx.gasLimit.toString());
    console.log('  Gas Price:', ethers.formatUnits(tx.gasPrice, 'gwei'), 'gwei');
    console.log('  Block Number:', tx.blockNumber);
    console.log('  Transaction Index:', tx.index);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Get receipt
    console.log('\n⏳ Fetching receipt...');
    const receipt = await ethers.provider.getTransactionReceipt(txHash);
    
    if (receipt) {
      console.log('✅ Receipt found!');
      console.log('Status:', receipt.status ? 'Success' : 'Failed');
      console.log('Gas Used:', receipt.gasUsed.toString());
      console.log('Logs:', receipt.logs.length);
      
      // Check if it's a token transfer
      if (receipt.logs.length > 0) {
        console.log('\n📋 Transaction Logs:');
        for (let i = 0; i < receipt.logs.length; i++) {
          console.log(`  Log ${i}:`);
          console.log('    Address:', receipt.logs[i].address);
          console.log('    Topics:', receipt.logs[i].topics);
        }
      }
    }

  } catch (error: any) {
    console.log('❌ Transaction not found or error:', error.message);
    console.log('\n💡 Possible reasons:');
    console.log('  1. Transaction is on a different network');
    console.log('  2. Transaction is still pending');
    console.log('  3. Transaction ID format is different (64 hex chars typical)');
    console.log('  4. Transaction may have been on a different blockchain');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
