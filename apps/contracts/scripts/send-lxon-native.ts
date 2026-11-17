import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Sending LXON on Native Blockchain to Founder...\n');

  const [sender] = await ethers.getSigners();
  console.log('Sender address:', sender.address);

  // Founder address
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  console.log('Founder address:', founderAddress);

  // LXON token address on native blockchain
  const lxonTokenAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  console.log('LXON token address:', lxonTokenAddress);

  // Get LXON contract
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check sender's LXON balance
  const senderLXONBalance = await lxonToken.balanceOf(sender.address);
  console.log('Sender LXON balance:', ethers.formatEther(senderLXONBalance), 'LXON');

  if (senderLXONBalance === 0n) {
    console.error('❌ No LXON tokens found!');
    process.exit(1);
  }

  // Amount to send (1000 LXON or all available if less)
  const amountToSend = senderLXONBalance < ethers.parseEther('1000') ? senderLXONBalance : ethers.parseEther('1000');
  console.log('Amount to send:', ethers.formatEther(amountToSend), 'LXON');
  console.log('USD value:', '$' + (Number(ethers.formatEther(amountToSend)) * 1.5).toFixed(2), 'at $1.50/LXON');

  // Check founder's current balance
  const founderBalanceBefore = await lxonToken.balanceOf(founderAddress);
  console.log('Founder balance before:', ethers.formatEther(founderBalanceBefore), 'LXON');

  // Send the transaction
  console.log('\n⏳ Sending LXON transaction...');
  const tx = await lxonToken.transfer(founderAddress, amountToSend);
  console.log('Transaction hash:', tx.hash);

  // Wait for confirmation
  console.log('Waiting for confirmation...');
  const receipt = await tx.wait();
  console.log('✅ Transaction confirmed!');
  console.log('Block number:', receipt.blockNumber);
  console.log('Gas used:', receipt.gasUsed.toString());

  // Check founder's balance after
  const founderBalanceAfter = await lxonToken.balanceOf(founderAddress);
  console.log('Founder balance after:', ethers.formatEther(founderBalanceAfter), 'LXON');
  console.log('LXON received:', ethers.formatEther(founderBalanceAfter - founderBalanceBefore), 'LXON');

  console.log('\n🎉 Transaction completed successfully!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  From: ${sender.address}`);
  console.log(`  To: ${founderAddress}`);
  console.log(`  Amount: ${ethers.formatEther(amountToSend)} LXON`);
  console.log(`  USD Value: $${(Number(ethers.formatEther(amountToSend)) * 1.5).toFixed(2)}`);
  console.log(`  TX Hash: ${tx.hash}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('\n📝 Note: Founder received LXON tokens worth $1,500 USD');
  console.log('   They can swap LXON for USD on their preferred exchange');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
