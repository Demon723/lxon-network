import { ethers } from 'hardhat';

async function main() {
  console.log('🎉 Verifying Correct LXON Token Contract\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // The correct token address from MetaMask
  const correctLXONAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  console.log('Token Address (from MetaMask):', correctLXONAddress);
  console.log('');

  // Check if contract exists
  console.log('🔍 Checking if contract exists...');
  const code = await ethers.provider.getCode(correctLXONAddress);
  console.log('Contract code length:', code.length);
  console.log('Has code:', code !== '0x' ? '✅ YES' : '❌ NO');
  console.log('');

  if (code === '0x') {
    console.log('❌ No contract at this address!');
    console.log('Please verify the address from MetaMask');
    return;
  }

  // Try to read as ERC20
  console.log('📊 Reading token information...');
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
    
    console.log('✅ Token Information:');
    console.log('  Name:', name);
    console.log('  Symbol:', symbol);
    console.log('  Decimals:', decimals);
    console.log('  Total Supply:', ethers.formatUnits(totalSupply, decimals));
    console.log('  Your Balance:', ethers.formatUnits(balance, decimals));
    console.log('');
    
    // Check if balance matches MetaMask
    const formattedBalance = ethers.formatUnits(balance, decimals);
    if (formattedBalance.includes('10000') || Number(formattedBalance) >= 9999) {
      console.log('🎉 FOUND YOUR 10,000 LXON!');
      console.log('   This is the correct token contract!');
      console.log('');
      console.log('✅ Ready to proceed with DEX operations!');
    } else {
      console.log('⚠️  Balance does not match MetaMask');
      console.log('   MetaMask shows: 10,000 LXON');
      console.log('   Contract shows:', formattedBalance, symbol);
    }
    
  } catch (e: any) {
    console.log('❌ Error reading token:', e.message);
    console.log('   This might not be a standard ERC20 token');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
