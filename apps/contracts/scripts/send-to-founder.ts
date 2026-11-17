import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Sending 1000 LXON to Founder Address...\n');

  const [sender] = await ethers.getSigners();
  console.log('Sender address:', sender.address);
  console.log('Sender balance:', ethers.formatEther(await ethers.provider.getBalance(sender.address)), 'ETH');

  // Founder address
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  console.log('Founder address:', founderAddress);

  // LXON token address from deployment
  const lxonTokenAddress = '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0';
  console.log('LXON token address:', lxonTokenAddress);

  // Amount to send (1000 LXON)
  const amountToSend = ethers.parseEther('1000');
  console.log('Amount to send:', ethers.formatEther(amountToSend), 'LXON ($1,500 USD at $1.50/LXON)');

  // Get the LXON token contract
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check sender's LXON balance
  const senderBalance = await lxonToken.balanceOf(sender.address);
  console.log('Sender LXON balance:', ethers.formatEther(senderBalance), 'LXON');

  if (senderBalance < amountToSend) {
    console.error('❌ Insufficient LXON balance!');
    console.log('Required:', ethers.formatEther(amountToSend), 'LXON');
    console.log('Available:', ethers.formatEther(senderBalance), 'LXON');
    process.exit(1);
  }

  // Check founder's current balance
  const founderBalanceBefore = await lxonToken.balanceOf(founderAddress);
  console.log('Founder balance before:', ethers.formatEther(founderBalanceBefore), 'LXON');

  // Send the transaction
  console.log('\n⏳ Sending transaction...');
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
  console.log('Transfer successful:', ethers.formatEther(founderBalanceAfter - founderBalanceBefore), 'LXON');

  console.log('\n🎉 Transaction completed successfully!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  From: ${sender.address}`);
  console.log(`  To: ${founderAddress}`);
  console.log(`  Amount: 1000 LXON ($1,500 USD)`);
  console.log(`  TX Hash: ${tx.hash}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
