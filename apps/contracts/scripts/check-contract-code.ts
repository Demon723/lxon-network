import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Contract Code...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  const ethereumLxonAddress = '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0';
  const lxonMainnetAddress = '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';

  console.log('Checking Ethereum deployment:', ethereumLxonAddress);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  try {
    const code = await ethers.provider.getCode(ethereumLxonAddress);
    console.log('Contract code length:', code.length);
    console.log('Has code:', code !== '0x' ? '✅ YES' : '❌ NO');
    
    if (code !== '0x') {
      console.log('✅ Contract exists at this address');
      console.log('Trying different interfaces...');
      
      // Try minimal ERC20 interface
      const minimalERC20 = [
        'function totalSupply() view returns (uint256)',
        'function balanceOf(address) view returns (uint256)',
        'function transfer(address, uint256) returns (bool)',
        'function allowance(address, address) view returns (uint256)',
        'function approve(address, uint256) returns (bool)',
        'function transferFrom(address, address, uint256) returns (bool)'
      ];
      
      const contract = new ethers.Contract(ethereumLxonAddress, minimalERC20, deployer);
      
      try {
        const totalSupply = await contract.totalSupply();
        console.log('✅ totalSupply():', totalSupply.toString());
      } catch (e) {
        console.log('❌ totalSupply() failed');
      }
      
      try {
        const balance = await contract.balanceOf(deployer.address);
        console.log('✅ balanceOf():', balance.toString());
      } catch (e) {
        console.log('❌ balanceOf() failed');
      }
    }
  } catch (e: any) {
    console.log('❌ Error:', e.message);
  }

  console.log('\nChecking LXON Mainnet deployment:', lxonMainnetAddress);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  try {
    const code = await ethers.provider.getCode(lxonMainnetAddress);
    console.log('Contract code length:', code.length);
    console.log('Has code:', code !== '0x' ? '✅ YES' : '❌ NO');
  } catch (e: any) {
    console.log('❌ Error:', e.message);
  }

  // Check which network we're on
  const network = await ethers.provider.getNetwork();
  console.log('\n🌐 Current Network:');
  console.log('Chain ID:', network.chainId);
  console.log('Network Name:', network.name);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
