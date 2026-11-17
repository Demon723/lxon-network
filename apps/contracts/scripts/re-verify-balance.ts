import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Re-verifying Balance on Correct Token Contract\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);
  console.log('');

  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Checking address:', targetAddress);
  console.log('Token contract:', lxonTokenAddress);
  console.log('');

  // Check balance again
  const minimalERC20 = [
    'function totalSupply() view returns (uint256)',
    'function balanceOf(address) view returns (uint256)',
    'function decimals() view returns (uint8)',
    'function symbol() view returns (string)',
    'function name() view returns (string)'
  ];
  
  const token = new ethers.Contract(lxonTokenAddress, minimalERC20, deployer);
  
  const balance = await token.balanceOf(targetAddress);
  const totalSupply = await token.totalSupply();
  const decimals = await token.decimals();
  const symbol = await token.symbol();
  
  console.log('📊 On-Chain Balance:');
  console.log('  Balance:', ethers.formatUnits(balance, decimals), symbol);
  console.log('  Total Supply:', ethers.formatUnits(totalSupply, decimals), symbol);
  console.log('');
  
  console.log('MetaMask shows: 10,000 LXON');
  console.log('On-chain shows:', ethers.formatUnits(balance, decimals), symbol);
  console.log('');
  
  if (ethers.formatUnits(balance, decimals) === '10000.0' || ethers.formatUnits(balance, decimals) === '10000') {
    console.log('🎉 BALANCE MATCHES! Ready to proceed!');
  } else {
    console.log('❌ BALANCE MISMATCH');
    console.log('');
    console.log('💡 POSSIBLE REASONS:');
    console.log('1. MetaMask is showing cached/stale data');
    console.log('2. MetaMask needs to be refreshed');
    console.log('3. Tokens are on a different contract');
    console.log('4. MetaMask is using a different RPC endpoint');
    console.log('');
    console.log('🔧 SUGGESTION:');
    console.log('  In MetaMask:');
    console.log('  1. Pull down to refresh');
    console.log('  2. Or remove and re-add the token');
    console.log('  3. Or switch networks and switch back');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
