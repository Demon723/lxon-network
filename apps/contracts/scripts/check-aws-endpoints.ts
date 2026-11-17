import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking AWS LXON Validator Endpoints\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('AWS Infrastructure Config:');
  console.log('  Region: eu-north-1');
  console.log('  Validator 1: 13.51.158.120:8546');
  console.log('  Validator 2: 16.170.246.246:8547');
  console.log('  Current Config: 16.171.20.249:8546');
  console.log('');

  // Try validator 1
  console.log('🔍 Testing Validator 1: http://13.51.158.120:8546');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const provider1 = new ethers.JsonRpcProvider('http://13.51.158.120:8546');
    const token1 = new ethers.Contract(lxonTokenAddress, ['function balanceOf(address) view returns (uint256)'], provider1);
    const balance1 = await token1.balanceOf(targetAddress);
    console.log('Balance:', ethers.formatEther(balance1));
    
    if (ethers.formatEther(balance1) === '10000.0' || ethers.formatEther(balance1) === '10000') {
      console.log('🎉 FOUND 10,000 LXON ON THIS ENDPOINT!');
    }
  } catch (e: any) {
    console.log('❌ Failed:', e.message);
  }
  console.log('');

  // Try validator 2
  console.log('🔍 Testing Validator 2: http://16.170.246.246:8547');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const provider2 = new ethers.JsonRpcProvider('http://16.170.246.246:8547');
    const token2 = new ethers.Contract(lxonTokenAddress, ['function balanceOf(address) view returns (uint256)'], provider2);
    const balance2 = await token2.balanceOf(targetAddress);
    console.log('Balance:', ethers.formatEther(balance2));
    
    if (ethers.formatEther(balance2) === '10000.0' || ethers.formatEther(balance2) === '10000') {
      console.log('🎉 FOUND 10,000 LXON ON THIS ENDPOINT!');
    }
  } catch (e: any) {
    console.log('❌ Failed:', e.message);
  }
  console.log('');

  // Try current config endpoint
  console.log('🔍 Testing Current Config: http://16.171.20.249:8546');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const provider3 = new ethers.JsonRpcProvider('http://16.171.20.249:8546');
    const token3 = new ethers.Contract(lxonTokenAddress, ['function balanceOf(address) view returns (uint256)'], provider3);
    const balance3 = await token3.balanceOf(targetAddress);
    console.log('Balance:', ethers.formatEther(balance3));
    
    if (ethers.formatEther(balance3) === '10000.0' || ethers.formatEther(balance3) === '10000') {
      console.log('🎉 FOUND 10,000 LXON ON THIS ENDPOINT!');
    }
  } catch (e: any) {
    console.log('❌ Failed:', e.message);
  }
  console.log('');

  console.log('💡 CONCLUSION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('If any endpoint shows 10,000 LXON, that\'s the one MetaMask is using.');
  console.log('Update Hardhat config to use that endpoint.');
  console.log('');
  console.log('If all show the same low balance, MetaMask might be:');
  console.log('1. Using a different endpoint not listed here');
  console.log('2. Showing cached/incorrect data');
  console.log('3. Connected to a different blockchain instance');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
