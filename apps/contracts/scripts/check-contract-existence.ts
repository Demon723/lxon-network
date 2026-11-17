import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Contract Existence on Both Networks...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  const addresses = [
    { name: 'Ethereum Deployment', address: '0x615341D8A07fe161A5FdFD87C97aA1E17D368Bf0', network: 'mainnet' },
    { name: 'LXON Mainnet Deployment', address: '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E', network: 'lxonMainnet' },
  ];

  for (const { name, address, network: networkName } of addresses) {
    console.log(`\n${name}: ${address}`);
    console.log('Network:', networkName);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    try {
      const code = await ethers.provider.getCode(address);
      const hasCode = code !== '0x';
      
      console.log('Contract Code Length:', code.length);
      console.log('Has Code:', hasCode ? '✅ YES' : '❌ NO');
      
      if (hasCode) {
        console.log('✅ Contract exists at this address');
        
        // Try to get basic info
        try {
          const minimalERC20 = [
            'function totalSupply() view returns (uint256)',
            'function balanceOf(address) view returns (uint256)'
          ];
          const contract = new ethers.Contract(address, minimalERC20, deployer);
          
          const totalSupply = await contract.totalSupply();
          const balance = await contract.balanceOf(deployer.address);
          
          console.log('Total Supply:', ethers.formatEther(totalSupply));
          console.log('Your Balance:', ethers.formatEther(balance));
          
          if (Number(ethers.formatEther(balance)) >= 99999) {
            console.log('🎉 FOUND 100,000+ LXON!');
          }
        } catch (e) {
          console.log('Could not read token info (might not be ERC20)');
        }
      } else {
        console.log('❌ No contract at this address');
      }
    } catch (e: any) {
      console.log('❌ Error:', e.message);
    }
  }

  console.log('\n💡 CONCLUSION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('If neither contract has code on their respective networks:');
  console.log('1. The deployment file might be outdated');
  console.log('2. Tokens might be on a different contract address');
  console.log('3. Need to find the actual deployed LXON token contract');
  console.log('');
  console.log('NEXT STEPS:');
  console.log('1. Check MetaMask for the actual token contract address');
  console.log('2. Look at Etherscan for Ethereum deployment');
  console.log('3. Check LXON blockchain explorer for LXON Mainnet deployment');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
