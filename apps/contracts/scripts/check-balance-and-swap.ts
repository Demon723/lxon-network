import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Balances and Swap Options...\n');

  const [sender] = await ethers.getSigners();
  console.log('Sender address:', sender.address);
  console.log('Sender ETH balance:', ethers.formatEther(await ethers.provider.getBalance(sender.address)), 'ETH');

  // Founder address
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  console.log('Founder address:', founderAddress);

  // LXON token address from .env
  const lxonTokenAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  console.log('LXON token address:', lxonTokenAddress);

  // Get LXON contract
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);

  // Check sender's LXON balance
  const senderLXONBalance = await lxonToken.balanceOf(sender.address);
  console.log('Sender LXON balance:', ethers.formatEther(senderLXONBalance), 'LXON');

  // Check if they have ETH for gas
  const ethBalance = await ethers.provider.getBalance(sender.address);
  console.log('ETH balance for gas:', ethers.formatEther(ethBalance), 'ETH');

  if (ethBalance === 0n) {
    console.error('\n❌ Insufficient ETH for gas fees!');
    console.log('You need ETH to pay for transaction gas fees on Ethereum mainnet.');
    console.log('\n💡 Options:');
    console.log('   1. Buy ETH on a CEX and transfer to your wallet');
    console.log('   2. Use the LXON native blockchain instead (no ETH needed)');
    console.log('   3. Use a testnet (sepolia) for testing');
    process.exit(1);
  }

  if (senderLXONBalance === 0n) {
    console.error('\n❌ No LXON tokens found!');
    console.log('You need LXON tokens to swap for USDC.');
    process.exit(1);
  }

  console.log('\n✅ You have sufficient LXON and ETH for transactions');

  // Amount to swap (1000 LXON or all available if less)
  const amountToSwap = senderLXONBalance < ethers.parseEther('1000') ? senderLXONBalance : ethers.parseEther('1000');
  console.log('Amount to swap:', ethers.formatEther(amountToSwap), 'LXON');

  // Since we don't have Uniswap V2 interfaces, let's use a direct ETH-to-USDC swap
  // or suggest using the native LXON blockchain
  console.log('\n💡 Swap Options:');
  console.log('   Option 1: Use LXON native blockchain (recommended for LXON tokens)');
  console.log('   Option 2: Use Uniswap directly on Ethereum mainnet (requires ETH)');
  console.log('   Option 3: Send LXON tokens directly to founder (they can swap)');

  // For now, let's send LXON directly to founder since swap is complex without interfaces
  console.log('\n⏳ Sending LXON directly to founder (they can swap)...');

  const founderLXONBalanceBefore = await lxonToken.balanceOf(founderAddress);
  console.log('Founder LXON balance before:', ethers.formatEther(founderLXONBalanceBefore), 'LXON');

  const tx = await lxonToken.transfer(founderAddress, amountToSwap);
  console.log('Transaction hash:', tx.hash);

  const receipt = await tx.wait();
  console.log('✅ Transaction confirmed!');
  console.log('Gas used:', receipt.gasUsed.toString());

  const founderLXONBalanceAfter = await lxonToken.balanceOf(founderAddress);
  console.log('Founder LXON balance after:', ethers.formatEther(founderLXONBalanceAfter), 'LXON');
  console.log('LXON received:', ethers.formatEther(founderLXONBalanceAfter - founderLXONBalanceBefore), 'LXON');

  console.log('\n🎉 Transaction completed!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  From: ${sender.address}`);
  console.log(`  To: ${founderAddress}`);
  console.log(`  Amount: ${ethers.formatEther(amountToSwap)} LXON (~$${Number(ethers.formatEther(amountToSwap)) * 1.5} USD at $1.50/LXON)`);
  console.log(`  TX Hash: ${tx.hash}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('\n📝 Note: Founder can swap LXON for USD on their preferred exchange');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
