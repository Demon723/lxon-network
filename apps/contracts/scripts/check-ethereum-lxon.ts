import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Ethereum Mainnet LXON Token...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Try the Ethereum deployment address
  const ethereumLxonAddress = '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0';
  
  console.log('Checking Ethereum LXON Token:', ethereumLxonAddress);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  try {
    const lxonToken = await ethers.getContractAt('IERC20', ethereumLxonAddress);
    
    const name = await lxonToken.name();
    const symbol = await lxonToken.symbol();
    const decimals = await lxonToken.decimals();
    const totalSupply = await lxonToken.totalSupply();
    const balance = await lxonToken.balanceOf(deployer.address);

    console.log('✅ Token found!');
    console.log('Name:', name);
    console.log('Symbol:', symbol);
    console.log('Decimals:', decimals);
    console.log('Total Supply:', ethers.formatUnits(totalSupply, decimals));
    console.log('Your Balance:', ethers.formatUnits(balance, decimals));
    console.log('');
    
    // Calculate if 100,000 LXON is possible
    const hundredThousand = ethers.parseUnits('100000', decimals);
    console.log('100,000 LXON in base units:', hundredThousand.toString());
    console.log('Total supply in base units:', totalSupply.toString());
    console.log('Can 100,000 LXON exist?', hundredThousand <= totalSupply ? '✅ YES' : '❌ NO');
    
    if (hundredThousand <= totalSupply) {
      console.log('💡 THIS IS THE CORRECT TOKEN CONTRACT!');
      console.log('The 100,000 LXON transfer likely happened on Ethereum Mainnet.');
    }

  } catch (e: any) {
    console.log('❌ Not a valid token contract on this network');
    console.log('Error:', e.message);
    console.log('');
    console.log('💡 This token might be on Ethereum Mainnet, not LXON Mainnet');
    console.log('Try running: npx hardhat run scripts/check-ethereum-lxon.ts --network mainnet');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
