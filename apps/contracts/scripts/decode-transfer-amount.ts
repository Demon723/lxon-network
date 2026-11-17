import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Decoding Transfer Amount from Transaction...\n');

  const txHash = '0x86607c374e184954fc6bcd2ed33a51a0a40d9026c0084339b8df0bc8e3c7d478';
  console.log('Transaction ID:', txHash);

  try {
    const receipt = await ethers.provider.getTransactionReceipt(txHash);
    
    // LXON token address
    const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
    const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);

    // Decode the transfer event
    // Transfer(address indexed from, address indexed to, uint256 value)
    const transferInterface = new ethers.Interface([
      'event Transfer(address indexed from, address indexed to, uint256 value)'
    ]);

    for (const log of receipt.logs) {
      if (log.address.toLowerCase() === lxonAddress.toLowerCase()) {
        try {
          const parsed = transferInterface.parseLog(log);
          console.log('✅ Transfer Event Decoded:');
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log('From:', parsed.args.from);
          console.log('To:', parsed.args.to);
          console.log('Amount:', ethers.formatEther(parsed.args.value), 'LXON');
          console.log('USD Value:', '$' + (Number(ethers.formatEther(parsed.args.value)) * 1.5).toFixed(2));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        } catch (e) {
          console.log('Could not parse log:', e);
        }
      }
    }

    // Check current balance
    const currentBalance = await lxonToken.balanceOf('0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27');
    console.log('\n📊 Current Balance:', ethers.formatEther(currentBalance), 'LXON');

  } catch (error: any) {
    console.log('❌ Error:', error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
