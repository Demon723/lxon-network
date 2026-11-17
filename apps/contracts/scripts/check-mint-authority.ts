import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Mint Authority Permissions...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';

  // Get LXON token contract with full ABI
  const lxonToken = await ethers.getContractAt('LXONNativeToken', lxonAddress);

  try {
    const owner = await lxonToken.owner();
    console.log('LXON Owner:', owner);
    console.log('Is Deployer Owner:', owner.toLowerCase() === deployer.address.toLowerCase() ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('Cannot check owner');
  }

  try {
    const mintAuthority = await lxonToken.mintAuthority();
    console.log('Mint Authority:', mintAuthority);
    console.log('Is Deployer Mint Authority:', mintAuthority.toLowerCase() === deployer.address.toLowerCase() ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('Cannot check mint authority');
  }

  try {
    const isAdditional = await lxonToken.additionalMintAuthorities(deployer.address);
    console.log('Is Deployer Additional Authority:', isAdditional ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('Cannot check additional authority');
  }

  // Try to mint if deployer has permissions
  console.log('\n💰 Attempting to mint 100 LXON tokens...');
  
  try {
    const mintTx = await lxonToken.mint(deployer.address, ethers.parseEther('100'));
    console.log('Mint transaction hash:', mintTx.hash);
    const receipt = await mintTx.wait();
    console.log('✅ Mint successful!');
    console.log('Gas used:', receipt.gasUsed.toString());
  } catch (error: any) {
    console.log('❌ Mint failed:', error.message);
    console.log('\n💡 Alternative: Try mintEcosystemReward if you have additional authority');
    
    try {
      const mintTx = await lxonToken.mintEcosystemReward(deployer.address, ethers.parseEther('100'), 'dex_liquidity');
      console.log('Ecosystem mint transaction hash:', mintTx.hash);
      const receipt = await mintTx.wait();
      console.log('✅ Ecosystem mint successful!');
      console.log('Gas used:', receipt.gasUsed.toString());
    } catch (error2: any) {
      console.log('❌ Ecosystem mint also failed:', error2.message);
    }
  }

  // Check final balance
  const finalBalance = await lxonToken.balanceOf(deployer.address);
  console.log('\nFinal LXON Balance:', ethers.formatEther(finalBalance));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
