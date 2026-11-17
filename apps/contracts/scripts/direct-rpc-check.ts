import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Direct RPC Balance Check (Alternative Method)\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Address:', targetAddress);
  console.log('Token:', lxonTokenAddress);
  console.log('');

  // Try direct RPC call
  console.log('🔍 Method 1: Direct RPC Call');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  try {
    const provider = ethers.provider;
    
    // Direct call to balanceOf
    const balanceCallData = {
      to: lxonTokenAddress,
      data: '0x70a08231' + targetAddress.slice(2).padStart(64, '0')
    };
    
    console.log('Call data:', balanceCallData.data);
    
    const result = await provider.call(balanceCallData);
    const balance = BigInt(result);
    
    console.log('Raw result:', result);
    console.log('Balance (raw):', balance.toString());
    console.log('Balance (formatted):', ethers.formatEther(balance));
    console.log('');
    
    if (ethers.formatEther(balance) === '10000.0' || ethers.formatEther(balance) === '10000') {
      console.log('🎉 FOUND 10,000 LXON via direct RPC!');
    } else {
      console.log('❌ Still not 10,000 LXON');
    }
    
  } catch (e: any) {
    console.log('❌ Direct RPC call failed:', e.message);
  }

  console.log('');

  // Try using the contract interface
  console.log('🔍 Method 2: Contract Interface Call');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  try {
    const minimalERC20 = [
      'function balanceOf(address) view returns (uint256)'
    ];
    
    const token = new ethers.Contract(lxonTokenAddress, minimalERC20, ethers.provider);
    const balance = await token.balanceOf(targetAddress);
    
    console.log('Balance (contract call):', ethers.formatEther(balance));
    console.log('');
    
    if (ethers.formatEther(balance) === '10000.0' || ethers.formatEther(balance) === '10000') {
      console.log('🎉 FOUND 10,000 LXON via contract call!');
    } else {
      console.log('❌ Still not 10,000 LXON');
    }
    
  } catch (e: any) {
    console.log('❌ Contract call failed:', e.message);
  }

  console.log('');

  // Check total supply
  console.log('🔍 Method 3: Check Total Supply');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  try {
    const minimalERC20 = [
      'function totalSupply() view returns (uint256)',
      'function balanceOf(address) view returns (uint256)'
    ];
    
    const token = new ethers.Contract(lxonTokenAddress, minimalERC20, ethers.provider);
    const totalSupply = await token.totalSupply();
    const balance = await token.balanceOf(targetAddress);
    
    console.log('Total Supply:', ethers.formatEther(totalSupply));
    console.log('Your Balance:', ethers.formatEther(balance));
    console.log('Your % of Supply:', (Number(balance) * 100 / Number(totalSupply)).toFixed(6) + '%');
    console.log('');
    
    // Check all holders (scan some addresses)
    console.log('🔍 Checking if balance is in a different account...');
    const possibleAddresses = [
      '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27', // Current
      '0x098Ae030804120Def93880a303788d24dc600d00', // From recent tx
      '0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5', // Owner
    ];
    
    for (const addr of possibleAddresses) {
      const bal = await token.balanceOf(addr);
      console.log(`${addr}:`, ethers.formatEther(bal));
      
      if (ethers.formatEther(bal) === '10000.0' || ethers.formatEther(bal) === '10000') {
        console.log('  🎉 FOUND 10,000 LXON at this address!');
      }
    }
    
  } catch (e: any) {
    console.log('❌ Supply check failed:', e.message);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('💡 CONCLUSION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('If all methods show the same low balance, then:');
  console.log('1. MetaMask might be showing incorrect/cached data');
  console.log('2. Or the tokens are on a different contract');
  console.log('3. Or MetaMask is using a different RPC endpoint');
  console.log('');
  console.log('If one method shows 10,000 LXON, we know the issue is specific to one method.');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
