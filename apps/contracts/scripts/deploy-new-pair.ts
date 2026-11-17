import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Deploying New Pair Contract (Updated with MINIMUM_LIQUIDITY = 1)\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const factoryAddress = '0xf8B86d766b718188458c6867576bec4D74866813';

  console.log('Deployer:', deployer.address);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('WETH Token:', wethAddress);
  console.log('');

  // Deploy new Pair contract
  console.log('⏳ Deploying new Pair contract...');
  const Pair = await ethers.getContractFactory('Pair');
  const pair = await Pair.deploy(lxonTokenAddress, wethAddress);
  await pair.waitForDeployment();
  const pairAddress = await pair.getAddress();
  
  console.log('✅ Pair deployed at:', pairAddress);
  console.log('');

  // Update factory to use new pair
  console.log('⏳ Updating factory with new pair...');
  const factory = await ethers.getContractAt('DEXFactory', factoryAddress);
  
  try {
    // Try to set the pair in factory
    const setPairTx = await factory.setPair(lxonTokenAddress, wethAddress, pairAddress);
    await setPairTx.wait();
    console.log('✅ Factory updated with new pair');
  } catch (e: any) {
    console.log('⚠️ Factory might not have setPair function:', e.message);
    console.log('   You may need to update factory contract or use router to create new pair');
  }
  console.log('');

  console.log('🎉 New Pair deployment complete!');
  console.log('');
  console.log('New Pair Address:', pairAddress);
  console.log('MINIMUM_LIQUIDITY:', 1);
  console.log('');
  console.log('Next steps:');
  console.log('1. Update UniversalRouter to use new pair address');
  console.log('2. Add liquidity with new pair');
  console.log('3. Execute swaps');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
