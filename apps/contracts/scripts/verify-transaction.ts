import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Verifying Transaction...\n');

  const txHash = '0x05d7f9a53176892746a4b4b59bb332e1c67b83b9c0be83d055e442fc00fa84fd';
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
            }
          } catch (e) {
            console.log('    Could not decode as Transfer event');
          }
        }
      }
    }

    // Update balance check
    console.log('\n📊 Checking current balance...');
    const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
    const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
    const currentBalance = await lxonToken.balanceOf('0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27');
    console.log('Current LXON Balance:', ethers.formatEther(currentBalance));

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
