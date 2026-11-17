import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Investigating XON Token (from MetaMask screenshot)\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // MetaMask showed both XON and LXON
  // Let's check if XON is the one with the large balance
  console.log('💡 MetaMask showed:');
  console.log('  XON: 5,973.922 XON');
  console.log('  LXON: 10,000 LXON');
  console.log('');
  console.log('Let me check if there are other token contracts on the network...');
  console.log('');

  // Try common XON token addresses or check native token
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  
  try {
    const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
    const balance = await nativeToken.balanceOf(deployer.address);
    const symbol = await nativeToken.symbol();
    const name = await nativeToken.name();
    
    console.log('Native Token:');
    console.log('  Address:', nativeTokenAddress);
    console.log('  Name:', name);
    console.log('  Symbol:', symbol);
    console.log('  Your Balance:', ethers.formatEther(balance));
    console.log('');
  } catch (e) {
    console.log('Could not read native token');
  }

  // Check the correct LXON address again with more detail
  const correctLXONAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  
  try {
    const minimalERC20 = [
      'function totalSupply() view returns (uint256)',
      'function balanceOf(address) view returns (uint256)',
      'function decimals() view returns (uint8)',
      'function symbol() view returns (string)',
      'function name() view returns (string)'
    ];
    
    const token = new ethers.Contract(correctLXONAddress, minimalERC20, deployer);
    
    const totalSupply = await token.totalSupply();
    const balance = await token.balanceOf(deployer.address);
    const decimals = await token.decimals();
    const symbol = await token.symbol();
    const name = await token.name();
    
    console.log('LXON Token (from MetaMask):');
    console.log('  Address:', correctLXONAddress);
    console.log('  Name:', name);
    console.log('  Symbol:', symbol);
    console.log('  Decimals:', decimals);
    console.log('  Total Supply:', ethers.formatUnits(totalSupply, decimals));
    console.log('  Your Balance:', ethers.formatUnits(balance, decimals));
    console.log('');
    
    // Check different accounts that might have the balance
    console.log('🔍 Checking if tokens are in a different account...');
    console.log('MetaMask shows "Account 2" - is this a different address?');
    console.log('Current address:', deployer.address);
    console.log('');
    
    console.log('💡 POSSIBLE ISSUES:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('1. MetaMask is showing a different account');
    console.log('   - "Account 2" might have a different address');
    console.log('   - We are checking 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27');
    console.log('   - Please verify the account address in MetaMask');
    console.log('');
    console.log('2. MetaMask is caching wrong balance');
    console.log('   - Try refreshing MetaMask');
    console.log('   - Or re-adding the token');
    console.log('');
    console.log('3. Tokens are on a different network');
    console.log('   - Even though it says LXON Mainnet');
    console.log('   - Might be a custom RPC with different chain ID');
    console.log('');
    console.log('4. The 10,000 LXON is actually XON tokens');
    console.log('   - XON showed 5,973.922 balance');
    console.log('   - Maybe the labeling is confused');
    
  } catch (e: any) {
    console.log('Error:', e.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📋 PLEASE VERIFY IN METAMASK:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. Click on your account name/address at the top');
  console.log('2. Copy the FULL address shown');
  console.log('3. Confirm it matches: 0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27');
  console.log('4. If different, provide the correct address');
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
