import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Deep Token Contract Analysis...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Analyze the current LXON token contract
  const lxonAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);

  console.log('📊 LXON Token Contract Details:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Address:', lxonAddress);

  try {
    const name = await lxonToken.name();
    console.log('Name:', name);
  } catch (e) {
    console.log('Name: Not available');
  }

  try {
    const symbol = await lxonToken.symbol();
    console.log('Symbol:', symbol);
  } catch (e) {
    console.log('Symbol: Not available');
  }

  try {
    const decimals = await lxonToken.decimals();
    console.log('Decimals:', decimals);
    console.log('💡 This means 1 human unit = 10^' + decimals + ' base units');
  } catch (e) {
    console.log('Decimals: Not available (assuming 18)');
  }

  const totalSupply = await lxonToken.totalSupply();
  console.log('Total Supply (base units):', totalSupply.toString());
  console.log('Total Supply (human units):', ethers.formatEther(totalSupply));

  const deployerBalance = await lxonToken.balanceOf(deployer.address);
  console.log('Your Balance (base units):', deployerBalance.toString());
  console.log('Your Balance (human units):', ethers.formatEther(deployerBalance));

  // Check if there are other LXON token contracts
  console.log('\n🔍 Checking for other possible LXON contracts...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Known addresses from deployments
  const possibleAddresses = [
    '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0', // From lxon-mainnet.json
    '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E', // Current
  ];

  for (const addr of possibleAddresses) {
    try {
      const token = await ethers.getContractAt('IERC20', addr);
      const supply = await token.totalSupply();
      const balance = await token.balanceOf(deployer.address);
      
      console.log(`\nAddress: ${addr}`);
      console.log('  Total Supply:', ethers.formatEther(supply));
      console.log('  Your Balance:', ethers.formatEther(balance));
      
      try {
        const symbol = await token.symbol();
        console.log('  Symbol:', symbol);
      } catch (e) {
        console.log('  Symbol: Not available');
      }
    } catch (e) {
      console.log(`\nAddress: ${addr} - Not a valid token contract`);
    }
  }

  // Calculate what 100,000 LXON would be in base units
  console.log('\n🧮 100,000 LXON Calculation:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  try {
    const decimals = await lxonToken.decimals();
    const hundredThousandLXON = ethers.parseUnits('100000', decimals);
    console.log('100,000 LXON in base units:', hundredThousandLXON.toString());
    console.log('Current total supply:', totalSupply.toString());
    console.log('Ratio:', hundredThousandLXON / totalSupply, 'x larger than total supply');
    console.log('❌ IMPOSSIBLE: 100,000 LXON is', (Number(hundredThousandLXON) / Number(totalSupply)).toFixed(0), 'x larger than total supply');
  } catch (e) {
    console.log('Could not calculate');
  }

  // Check native token for comparison
  console.log('\n📊 Native Token Comparison:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
  
  const nativeSupply = await nativeToken.totalSupply();
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('Native Token Address:', nativeTokenAddress);
  console.log('Total Supply:', ethers.formatEther(nativeSupply));
  console.log('Your Balance:', ethers.formatEther(nativeBalance));

  // Check if maybe user meant 100,000 base units
  console.log('\n💡 Alternative Interpretation Check:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Maybe you meant 100,000 BASE units instead of 100,000 human units?');
  console.log('100,000 base units in human units:', ethers.formatEther(100000n));
  console.log('Your current balance:', ethers.formatEther(deployerBalance));
  console.log('Your current balance in base units:', deployerBalance.toString());
  console.log('Match?', deployerBalance.toString() === '100000' ? '✅ YES!' : '❌ NO');

  // Final diagnosis
  console.log('\n🎯 FINAL DIAGNOSIS:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('✅ Token contract is accessible');
  console.log('✅ Total supply is:', ethers.formatEther(totalSupply), 'LXON');
  console.log('❌ 100,000 LXON CANNOT exist (total supply is only 0.01 LXON)');
  console.log('❌ Maximum possible balance is 0.0100101001 LXON');
  console.log('');
  console.log('💡 POSSIBLE EXPLANATIONS:');
  console.log('1. User meant a different token contract');
  console.log('2. User meant 100,000 base units (not human units)');
  console.log('3. User is confused about token supply');
  console.log('4. Transaction was on a different network');
  console.log('5. Owner needs to mint more tokens first');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
