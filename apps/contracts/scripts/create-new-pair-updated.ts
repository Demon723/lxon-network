import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Creating New Pair with Updated Contract (MINIMUM_LIQUIDITY = 1)\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';
  const factoryAddress = '0xf8B86d766b718188458c6867576bec4D74866813';

  console.log('Deployer:', deployer.address);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('WETH Token:', wethAddress);
  console.log('Factory:', factoryAddress);
  console.log('');

  // Get factory contract
  const factory = await ethers.getContractAt('DEXFactory', factoryAddress);

  // Check if pair already exists
  const existingPair = await factory.getPair(lxonTokenAddress, wethAddress);
  console.log('Existing pair:', existingPair);
  console.log('');

  if (existingPair !== ethers.ZeroAddress) {
    console.log('⚠️ Pair already exists');
    console.log('   To use updated Pair contract, we need to:');
    console.log('   1. Create a new pair with different token order');
    console.log('   2. Or modify factory to redeploy pairs');
    console.log('');
    console.log('   Creating new pair with swapped order for testing...');
    
    // Try with swapped order (might create different pair)
    try {
      const createTx = await factory.createPair(wethAddress, lxonTokenAddress);
      console.log('Transaction hash:', createTx.hash);
      await createTx.wait();
      console.log('✅ New pair created!');
      
      const newPair = await factory.getPair(wethAddress, lxonTokenAddress);
      console.log('New pair address:', newPair);
    } catch (e: any) {
      console.log('❌ Create failed:', e.message);
      console.log('   Pair exists in both directions');
    }
  } else {
    console.log('⏳ Creating new pair...');
    const createTx = await factory.createPair(lxonTokenAddress, wethAddress);
    console.log('Transaction hash:', createTx.hash);
    await createTx.wait();
    console.log('✅ Pair created!');
    
    const newPair = await factory.getPair(lxonTokenAddress, wethAddress);
    console.log('New pair address:', newPair);
  }
  console.log('');

  console.log('🎉 Pair creation complete!');
  console.log('');
  console.log('Note: The factory deploys the latest compiled Pair contract');
  console.log('MINIMUM_LIQUIDITY is now set to 1 in the compiled contract');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
