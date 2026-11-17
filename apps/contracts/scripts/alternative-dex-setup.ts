import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Exploring Alternative DEX Setup Options...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Check all available tokens
  console.log('📊 Checking Available Tokens...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);

  console.log('LXON Balance:', ethers.formatEther(lxonBalance));
  console.log('Native Balance:', ethers.formatEther(nativeBalance));
  console.log('');

  // Check if we can create a pair with different amounts
  console.log('💡 ALTERNATIVE OPTIONS:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  console.log('OPTION 1: Use Available Native Token');
  console.log('  - You have 0.0167 Native tokens');
  console.log('  - Could create Native/Native pair (if supported)');
  console.log('  - Or find another token with balance');
  console.log('');

  console.log('OPTION 2: Deploy on Local Network');
  console.log('  - Start local Hardhat node');
  console.log('  - Mint unlimited tokens for testing');
  console.log('  - Demonstrate full DEX functionality');
  console.log('  - Then replicate on mainnet with real tokens');
  console.log('');

  console.log('OPTION 3: Create Simulation Mode');
  console.log('  - Use the deployed contracts');
  console.log('  - Simulate swaps without real liquidity');
  console.log('  - Demonstrate calculations and workflows');
  console.log('');

  console.log('OPTION 4: Wait for Owner Minting');
  console.log('  - Continue waiting for owner response');
  console.log('  - Monitor blockchain for token minting');
  console.log('');

  console.log('OPTION 5: Use Native Token as Quote');
  console.log('  - Native token has 0.0167 balance');
  console.log('  - Could potentially create pair with very small amounts');
  console.log('  - May require contract modifications for small amounts');
  console.log('');

  // Check local network option
  console.log('🚀 RECOMMENDED: Local Network Demo');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('Benefits:');
  console.log('  ✅ Can mint unlimited tokens');
  console.log('  ✅ No waiting for owner');
  console.log('  ✅ Full DEX demonstration');
  console.log('  ✅ Test all features safely');
  console.log('  ✅ Document workflows for mainnet deployment');
  console.log('');
  console.log('Steps:');
  console.log('  1. Start local node: npx hardhat node');
  console.log('  2. Deploy DEX on localhost');
  console.log('  3. Mint 100,000 LXON');
  console.log('  4. Mint 100,000 Native tokens');
  console.log('  5. Add liquidity');
  console.log('  6. Execute swaps');
  console.log('  7. Demonstrate full workflow');
  console.log('');

  // Ask user for preference
  console.log('🎯 WHICH OPTION WOULD YOU LIKE?');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('A: Deploy and demo on local network (RECOMMENDED)');
  console.log('B: Try to add liquidity with current tiny amounts');
  console.log('C: Create simulation mode without real transactions');
  console.log('D: Continue waiting for owner minting');
  console.log('E: Explore other token contracts on network');
  console.log('');

  console.log('Please let me know which option you prefer (A, B, C, D, or E)');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
