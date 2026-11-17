import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Ethereum Mainnet LXON Balance...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Try to check the Ethereum deployment address
  const ethereumLxonAddress = '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0';
  
  console.log('Checking Ethereum Mainnet LXON Token:', ethereumLxonAddress);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Network info
  const network = await ethers.provider.getNetwork();
  console.log('Network:', network.name);
  console.log('Chain ID:', network.chainId);
  console.log('');

  try {
    // Use minimal ERC20 interface
    const minimalERC20 = [
      'function totalSupply() view returns (uint256)',
      'function balanceOf(address) view returns (uint256)',
      'function decimals() view returns (uint8)',
      'function symbol() view returns (string)',
      'function name() view returns (string)'
    ];
    
    const contract = new ethers.Contract(ethereumLxonAddress, minimalERC20, deployer);
    
    try {
      const totalSupply = await contract.totalSupply();
      console.log('✅ Total Supply:', ethers.formatEther(totalSupply));
    } catch (e) {
      console.log('❌ totalSupply() failed');
    }
    
    try {
      const balance = await contract.balanceOf(deployer.address);
      console.log('✅ Your Balance:', ethers.formatEther(balance));
      
      // Check if balance is significant
      if (balance > 0) {
        console.log('💡 YOU HAVE LXON ON ETHEREUM MAINNET!');
        console.log('   This might be where the 100,000 LXON transfer went.');
        
        // Check if it's 100,000
        const formattedBalance = ethers.formatEther(balance);
        if (formattedBalance.includes('100000') || Number(formattedBalance) >= 99999) {
          console.log('🎉 FOUND 100,000 LXON ON ETHEREUM MAINNET!');
        }
      }
    } catch (e) {
      console.log('❌ balanceOf() failed');
    }
    
    try {
      const decimals = await contract.decimals();
      console.log('✅ Decimals:', decimals);
    } catch (e) {
      console.log('❌ decimals() failed');
    }
    
    try {
      const symbol = await contract.symbol();
      console.log('✅ Symbol:', symbol);
    } catch (e) {
      console.log('❌ symbol() failed');
    }
    
    try {
      const name = await contract.name();
      console.log('✅ Name:', name);
    } catch (e) {
      console.log('❌ name() failed');
    }

  } catch (e: any) {
    console.log('❌ Contract call failed:', e.message);
    console.log('');
    console.log('💡 Possible reasons:');
    console.log('1. Contract does not exist on this network');
    console.log('2. We are on the wrong network');
    console.log('3. Contract ABI mismatch');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
