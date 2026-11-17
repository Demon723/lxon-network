import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Sending USDC to Founder Address...\n');

  const [sender] = await ethers.getSigners();
  console.log('Sender address:', sender.address);
  console.log('Sender ETH balance:', ethers.formatEther(await ethers.provider.getBalance(sender.address)), 'ETH');

  // Founder address
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  console.log('Founder address:', founderAddress);

  // USDC address on Ethereum mainnet
  const usdcAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
  console.log('USDC token address:', usdcAddress);

  // Amount to send ($1,500 USD in USDC, 6 decimals)
  const amountToSend = ethers.parseUnits('1500', 6);
  console.log('Amount to send:', ethers.formatUnits(amountToSend, 6), 'USDC ($1,500 USD)');

  // Get USDC contract
  const usdcToken = await ethers.getContractAt('IERC20', usdcAddress);

  // Check sender's USDC balance
  const senderBalance = await usdcToken.balanceOf(sender.address);
  console.log('Sender USDC balance:', ethers.formatUnits(senderBalance, 6), 'USDC');

  if (senderBalance < amountToSend) {
    console.error('❌ Insufficient USDC balance!');
    console.log('Required:', ethers.formatUnits(amountToSend, 6), 'USDC');
    console.log('Available:', ethers.formatUnits(senderBalance, 6), 'USDC');
    console.log('\n💡 To get USDC, you can:');
    console.log('   1. Buy USDC on a CEX and transfer to your wallet');
    console.log('   2. Swap ETH for USDC on Uniswap');
    console.log('   3. Use a bridge to transfer USDC from another network');
    process.exit(1);
  }

  // Check founder's current balance
  const founderBalanceBefore = await usdcToken.balanceOf(founderAddress);
  console.log('Founder balance before:', ethers.formatUnits(founderBalanceBefore, 6), 'USDC');

  // Send the transaction
  console.log('\n⏳ Sending USDC transaction...');
  const tx = await usdcToken.transfer(founderAddress, amountToSend);
  console.log('Transaction hash:', tx.hash);

  // Wait for confirmation
  console.log('Waiting for confirmation...');
  const receipt = await tx.wait();
  console.log('✅ Transaction confirmed!');
  console.log('Block number:', receipt.blockNumber);
  console.log('Gas used:', receipt.gasUsed.toString());

  // Check founder's balance after
  const founderBalanceAfter = await usdcToken.balanceOf(founderAddress);
  console.log('Founder balance after:', ethers.formatUnits(founderBalanceAfter, 6), 'USDC');
  console.log('USDC received:', ethers.formatUnits(founderBalanceAfter - founderBalanceBefore, 6), 'USDC');

  console.log('\n🎉 Transaction completed successfully!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  From: ${sender.address}`);
  console.log(`  To: ${founderAddress}`);
  console.log(`  Amount: 1500 USDC ($1,500 USD)`);
  console.log(`  TX Hash: ${tx.hash}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
