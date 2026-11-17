import { ethers } from 'hardhat';

async function main() {
  console.log('💰 Checking Current Token Balances...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('Current Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native:', ethers.formatEther(nativeBalance));

  // Load price oracle
  const fs = require('fs');
  const advancedPath = './deployments/dex-advanced-724.json';
  const advancedInfo = JSON.parse(fs.readFileSync(advancedPath, 'utf8'));
  const oracle = await ethers.getContractAt('PriceOracle', advancedInfo.contracts.PriceOracle);

  // Calculate USD value
  const lxonUSD = await oracle.getPriceInUSD(lxonAddress, lxonBalance);
  const nativeUSD = await oracle.getPriceInUSD(nativeTokenAddress, nativeBalance);
  
  console.log('\nUSD Values:');
  console.log('LXON:', '$' + ethers.formatUnits(lxonUSD, 18));
  console.log('Native:', '$' + ethers.formatUnits(nativeUSD, 18));
  console.log('Total:', '$' + ethers.formatUnits(lxonUSD + nativeUSD, 18));

  // Check if sufficient for liquidity
  const minRequired = ethers.parseEther('1'); // At least 1 token
  const recommended = ethers.parseEther('100'); // Recommended 100 tokens
  
  console.log('\n📊 Liquidity Readiness:');
  console.log('Minimum required (1 token each):');
  console.log('  LXON:', lxonBalance >= minRequired ? '✅ Sufficient' : '❌ Insufficient');
  console.log('  Native:', nativeBalance >= minRequired ? '✅ Sufficient' : '❌ Insufficient');
  
  console.log('\nRecommended (100 tokens each):');
  console.log('  LXON:', lxonBalance >= recommended ? '✅ Sufficient' : '❌ Insufficient');
  console.log('  Native:', nativeBalance >= recommended ? '✅ Sufficient' : '❌ Insufficient');

  if (lxonBalance >= minRequired && nativeBalance >= minRequired) {
    console.log('\n🎉 Ready to add liquidity!');
    console.log('💡 Run: npx hardhat run scripts/add-liquidity-dex.ts --network lxonMainnet');
  } else {
    console.log('\n⚠️  Still need more tokens for liquidity operations');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
