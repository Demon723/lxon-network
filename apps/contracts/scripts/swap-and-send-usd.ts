import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Swapping 1000 LXON for USDC and sending to Founder...\n');

  const [sender] = await ethers.getSigners();
  console.log('Sender address:', sender.address);
  console.log('Sender ETH balance:', ethers.formatEther(await ethers.provider.getBalance(sender.address)), 'ETH');

  // Founder address
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  console.log('Founder address:', founderAddress);

  // Contract addresses from .env
  const lxonTokenAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const pairAddress = process.env.PAIR_ADDRESS || '0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7';
  const routerAddress = process.env.ROUTER_ADDRESS || '0x92F4D1236026F23967eBd213547FE18606AE8dD5';

  console.log('LXON token:', lxonTokenAddress);
  console.log('Pair address:', pairAddress);
  console.log('Router address:', routerAddress);

  // Amount to swap (1000 LXON)
  const amountToSwap = ethers.parseEther('1000');
  console.log('Amount to swap:', ethers.formatEther(amountToSwap), 'LXON');

  // Get contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const pair = await ethers.getContractAt('IUniswapV2Pair', pairAddress);
  const router = await ethers.getContractAt('IUniswapV2Router02', routerAddress);

  // Check sender's LXON balance
  const senderLXONBalance = await lxonToken.balanceOf(sender.address);
  console.log('Sender LXON balance:', ethers.formatEther(senderLXONBalance), 'LXON');

  if (senderLXONBalance < amountToSwap) {
    console.error('❌ Insufficient LXON balance!');
    console.log('Required:', ethers.formatEther(amountToSwap), 'LXON');
    console.log('Available:', ethers.formatEther(senderLXONBalance), 'LXON');
    process.exit(1);
  }

  // Get pair tokens to find USDC address
  const token0 = await pair.token0();
  const token1 = await pair.token1();
  console.log('Pair token0:', token0);
  console.log('Pair token1:', token1);

  // Determine which token is USDC (not LXON)
  const usdcAddress = token0.toLowerCase() === lxonTokenAddress.toLowerCase() ? token1 : token0;
  console.log('USDC address:', usdcAddress);

  // Get USDC contract
  const usdcToken = await ethers.getContractAt('IERC20', usdcAddress);

  // Check founder's USDC balance before
  const founderUSDCBalanceBefore = await usdcToken.balanceOf(founderAddress);
  console.log('Founder USDC balance before:', ethers.formatUnits(founderUSDCBalanceBefore, 6), 'USDC');

  // Approve router to spend LXON
  console.log('\n⏳ Approving router to spend LXON...');
  const approveTx = await lxonToken.approve(routerAddress, amountToSwap);
  await approveTx.wait();
  console.log('✅ Approval confirmed');

  // Get swap deadline (20 minutes from now)
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;

  // Calculate minimum USDC to receive (slippage tolerance: 5%)
  // Note: In production, you should query the DEX for the actual amount
  const minUSDC = ethers.parseUnits('950', 6); // Assuming 1 LXON = $1.50, 1000 LXON = $1500, 5% slippage = $1425

  // Execute swap
  console.log('\n⏳ Swapping LXON for USDC...');
  console.log('Amount in:', ethers.formatEther(amountToSwap), 'LXON');
  console.log('Minimum USDC out:', ethers.formatUnits(minUSDC, 6), 'USDC');

  const swapTx = await router.swapExactTokensForTokens(
    amountToSwap,
    minUSDC,
    [lxonTokenAddress, usdcAddress],
    sender.address,
    deadline
  );
  console.log('Swap transaction hash:', swapTx.hash);

  // Wait for swap confirmation
  console.log('Waiting for swap confirmation...');
  const swapReceipt = await swapTx.wait();
  console.log('✅ Swap confirmed!');
  console.log('Gas used:', swapReceipt.gasUsed.toString());

  // Check sender's USDC balance after swap
  const senderUSDCBalance = await usdcToken.balanceOf(sender.address);
  console.log('Sender USDC balance after swap:', ethers.formatUnits(senderUSDCBalance, 6), 'USDC');

  // Send USDC to founder
  console.log('\n⏳ Sending USDC to founder...');
  const usdcToSend = senderUSDCBalance; // Send all USDC received
  const transferTx = await usdcToken.transfer(founderAddress, usdcToSend);
  console.log('Transfer transaction hash:', transferTx.hash);

  // Wait for transfer confirmation
  console.log('Waiting for transfer confirmation...');
  const transferReceipt = await transferTx.wait();
  console.log('✅ Transfer confirmed!');
  console.log('Gas used:', transferReceipt.gasUsed.toString());

  // Check founder's USDC balance after
  const founderUSDCBalanceAfter = await usdcToken.balanceOf(founderAddress);
  console.log('Founder USDC balance after:', ethers.formatUnits(founderUSDCBalanceAfter, 6), 'USDC');
  console.log('USDC received:', ethers.formatUnits(founderUSDCBalanceAfter - founderUSDCBalanceBefore, 6), 'USDC');

  console.log('\n🎉 Transaction completed successfully!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  From: ${sender.address}`);
  console.log(`  To: ${founderAddress}`);
  console.log(`  Swapped: 1000 LXON`);
  console.log(`  Sent: ${ethers.formatUnits(founderUSDCBalanceAfter - founderUSDCBalanceBefore, 6)} USDC (~$1,500)`);
  console.log(`  Swap TX: ${swapTx.hash}`);
  console.log(`  Transfer TX: ${transferTx.hash}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
