import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Decoding Transaction...\n');

  const txHash = '0xf3e49a5ce5c588d5d245f3f038dedcae48cd24395f68ecf3dad116fd574bb604';
  console.log('Transaction ID:', txHash);
  console.log('');

  try {
    console.log('⏳ Fetching transaction...');
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
        
        // Try to decode as ERC20 Transfer
        const transferInterface = new ethers.Interface([
          'event Transfer(address indexed from, address indexed to, uint256 value)'
        ]);

        for (let i = 0; i < receipt.logs.length; i++) {
          const log = receipt.logs[i];
          console.log(`\n  Log ${i}:`);
          console.log('    Address:', log.address);
          console.log('    Topics:', log.topics);
          
          try {
            const parsed = transferInterface.parseLog(log);
            console.log('    Decoded Transfer:');
            console.log('      From:', parsed.args.from);
            console.log('      To:', parsed.args.to);
            console.log('      Amount:', ethers.formatEther(parsed.args.value));
            console.log('      USD Value:', '$' + (Number(ethers.formatEther(parsed.args.value)) * 1.5).toFixed(2));
            
            // Check if recipient is our address
            const deployerAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
            if (parsed.args.to.toLowerCase() === deployerAddress.toLowerCase()) {
              console.log('    ✅ THIS IS TO YOUR ADDRESS!');
              
              // Check if it's 10,000 LXON
              const amount = ethers.formatEther(parsed.args.value);
              if (amount.includes('10000') || Number(amount) >= 9999) {
                console.log('    🎉 FOUND 10,000 LXON TRANSFER!');
                console.log('    Token Contract:', log.address);
              }
            }
          } catch (e) {
            console.log('    Could not decode as Transfer event');
          }
        }
      }
    }

    // Update balance check
    console.log('\n📊 Checking current balance on this token contract...');
    if (receipt && receipt.logs.length > 0) {
      const tokenAddress = receipt.logs[0].address;
      const lxonToken = await ethers.getContractAt('IERC20', tokenAddress);
      const currentBalance = await lxonToken.balanceOf('0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27');
      console.log('Token Contract:', tokenAddress);
      console.log('Current Balance:', ethers.formatEther(currentBalance));
    }

  } catch (error: any) {
    console.log('❌ Transaction not found or error:', error.message);
    console.log('\n💡 Possible reasons:');
    console.log('  1. Transaction is on a different network');
    console.log('  2. Transaction is still pending');
    console.log('  3. Wrong transaction hash format');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
