import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Sending 1,000 LXON to Founder\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('From:', targetAddress);
  console.log('To:', founderAddress);
  console.log('Amount: 1,000 LXON');
  console.log('USD Value at $1.50/LXON: $1,500');
  console.log('');

  // Get token contract
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check balance
  const balance = await lxonToken.balanceOf(targetAddress);
  console.log('Current Balance:', ethers.formatEther(balance), 'LXON');
  console.log('');

  const amountToSend = ethers.parseEther('1000');

  if (balance < amountToSend) {
    console.log('❌ Insufficient balance');
    console.log('   Have:', ethers.formatEther(balance));
    console.log('   Need:', ethers.formatEther(amountToSend));
    return;
  }

  console.log('✅ Sufficient balance');
  console.log('');

  // Send tokens
  console.log('⏳ Sending 1,000 LXON to founder...');
  try {
    const tx = await lxonToken.transfer(founderAddress, amountToSend);
    console.log('Transaction hash:', tx.hash);
    console.log('⏳ Waiting for confirmation...');
    
    const receipt = await tx.wait();
    console.log('✅ Transfer successful!');
    console.log('Gas used:', receipt.gasUsed.toString());
    console.log('');

    // Verify new balance
    const newBalance = await lxonToken.balanceOf(targetAddress);
    console.log('New Balance:', ethers.formatEther(newBalance), 'LXON');
    console.log('');

    // Check founder balance
    const founderBalance = await lxonToken.balanceOf(founderAddress);
    console.log('Founder Balance:', ethers.formatEther(founderBalance), 'LXON');
    console.log('');

    console.log('🎉 TRANSACTION COMPLETE!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('Sent: 1,000 LXON');
    console.log('To:', founderAddress);
    console.log('USD Value: $1,500 (at $1.50/LXON)');
    console.log('Status: ✅ Confirmed on-chain');
    console.log('');
    console.log('Note: This is a direct LXON transfer, not USD conversion.');
    console.log('USD conversion through DEX requires native token liquidity.');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  } catch (error: any) {
    console.log('❌ Transfer failed:', error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
