import { ethers } from 'hardhat';

async function main() {
  console.log('🎯 GUIDE: Minting Tokens for DEX Operations\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  console.log('Current Account:', deployer.address);

  const ownerAddress = '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5';
  const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';

  console.log('Owner Address:', ownerAddress);
  console.log('LXON Token:', lxonAddress);
  console.log('');

  // Check current supply
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const totalSupply = await lxonToken.totalSupply();
  const ownerBalance = await lxonToken.balanceOf(ownerAddress);
  const deployerBalance = await lxonToken.balanceOf(deployer.address);

  console.log('📊 Current State:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Total Supply:', ethers.formatEther(totalSupply), 'LXON');
  console.log('Owner Balance:', ethers.formatEther(ownerBalance), 'LXON');
  console.log('Your Balance:', ethers.formatEther(deployerBalance), 'LXON');
  console.log('');

  console.log('🔍 PROBLEM:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('❌ Total supply is only 0.01 LXON');
  console.log('❌ Required for DEX: 100+ LXON');
  console.log('❌ Gap: Need ~10,000x more LXON');
  console.log('');

  console.log('💡 SOLUTION: OWNER MUST MINT TOKENS');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('STEP 1: Owner accesses LXON Native Token contract');
  console.log('  Contract: 0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E');
  console.log('');
  console.log('STEP 2: Owner calls mint function');
  console.log('  Function: mint(address to, uint256 amount)');
  console.log('  OR: mintEcosystemReward(address to, uint256 amount, string reason)');
  console.log('');
  console.log('STEP 3: Mint to your address');
  console.log('  To:', deployer.address);
  console.log('  Amount: 1000 LXON (recommended for DEX testing)');
  console.log('  OR: 100000 LXON (for full original goal)');
  console.log('');

  console.log('📝 TRANSACTION EXAMPLE:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('If owner has access to the contract, they can call:');
  console.log('');
  console.log('mint(');
  console.log('  to: "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27",');
  console.log('  amount: 100000000000000000000000000  // 100,000 LXON in wei');
  console.log(')');
  console.log('');
  console.log('OR using ecosystem reward:');
  console.log('');
  console.log('mintEcosystemReward(');
  console.log('  to: "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27",');
  console.log('  amount: 100000000000000000000000000,  // 100,000 LXON');
  console.log('  reason: "DEX liquidity provision"');
  console.log(')');
  console.log('');

  console.log('🚀 AFTER MINTING:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. Run balance check to verify:');
  console.log('   npx hardhat run scripts/check-current-balances.ts --network lxonMainnet');
  console.log('');
  console.log('2. Add liquidity:');
  console.log('   npx hardhat run scripts/add-liquidity-dex.ts --network lxonMainnet');
  console.log('');
  console.log('3. Start swapping:');
  console.log('   npx hardhat run scripts/dex-full-workflow.ts --network lxonMainnet');
  console.log('');
  console.log('4. Execute original goal (swap 1000 LXON for USD):');
  console.log('   npx hardhat run scripts/swap-and-send-usd.ts --network lxonMainnet');

  console.log('\n📋 OWNER CONTACT INFORMATION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Owner Address:', ownerAddress);
  console.log('Your Address:', deployer.address);
  console.log('Required Amount: 100,000 LXON (for original goal)');
  console.log('Minimum for DEX: 1 LXON');
  console.log('Recommended for DEX: 100 LXON');
  console.log('');

  console.log('💬 MESSAGE TO OWNER:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('I need 100,000 LXON minted to my address');
  console.log('(0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27)');
  console.log('for DEX liquidity provision and testing.');
  console.log('');
  console.log('Purpose: Adding liquidity to LXON/Native trading pair');
  console.log('and enabling DEX operations on LXON Mainnet.');
  console.log('');
  console.log('Please use mint() or mintEcosystemReward() function');
  console.log('on the LXON token contract.');
  console.log('');

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
