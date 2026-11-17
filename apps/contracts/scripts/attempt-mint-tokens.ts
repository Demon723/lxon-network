import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Attempting to Mine/Mint LXON Tokens\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';

  console.log('Attempting to mint 10,000 LXON to:', targetAddress);
  console.log('');

  // Try different minting approaches
  console.log('🔍 Method 1: Try mint() function');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const mintInterface = new ethers.Interface([
      'function mint(address to, uint256 amount) returns (bool)'
    ]);
    
    const mintData = mintInterface.encodeFunctionData('mint', [
      targetAddress,
      ethers.parseEther('10000')
    ]);
    
    const tx = await deployer.sendTransaction({
      to: lxonTokenAddress,
      data: mintData
    });
    
    console.log('Transaction sent:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ Mint successful!');
    console.log('Gas used:', receipt.gasUsed.toString());
  } catch (e: any) {
    console.log('❌ Mint failed:', e.message);
    console.log('   (This is expected if you\'re not the owner or don\'t have mint authority)');
  }
  console.log('');

  console.log('🔍 Method 2: Try mintEcosystemReward() function');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const mintInterface = new ethers.Interface([
      'function mintEcosystemReward(address to, uint256 amount, string reason) returns (bool)'
    ]);
    
    const mintData = mintInterface.encodeFunctionData('mintEcosystemReward', [
      targetAddress,
      ethers.parseEther('10000'),
      'DEX liquidity provision'
    ]);
    
    const tx = await deployer.sendTransaction({
      to: lxonTokenAddress,
      data: mintData
    });
    
    console.log('Transaction sent:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ Mint successful!');
    console.log('Gas used:', receipt.gasUsed.toString());
  } catch (e: any) {
    console.log('❌ Mint failed:', e.message);
    console.log('   (This is expected if you\'re not the owner or don\'t have mint authority)');
  }
  console.log('');

  console.log('🔍 Method 3: Check if deployer has mint authority');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  try {
    const token = await ethers.getContractAt('IERC20', lxonTokenAddress);
    
    // Try to call owner function if it exists
    try {
      const ownerInterface = new ethers.Interface([
        'function owner() view returns (address)'
      ]);
      const ownerData = ownerInterface.encodeFunctionData('owner');
      const ownerResult = await ethers.provider.call({
        to: lxonTokenAddress,
        data: ownerData
      });
      const ownerAddress = ethers.AbiCoder.defaultAbiCoder().decode(['address'], ownerResult)[0];
      console.log('Token Owner:', ownerAddress);
      console.log('Deployer is Owner:', ownerAddress.toLowerCase() === deployer.address.toLowerCase() ? '✅ YES' : '❌ NO');
    } catch (e) {
      console.log('Could not check owner (function might not exist)');
    }
  } catch (e: any) {
    console.log('Error checking authority:', e.message);
  }
  console.log('');

  console.log('💡 CONCLUSION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('If minting failed, you likely need:');
  console.log('1. Owner authority (to call mint functions)');
  console.log('2. Or transfer from the address that has the tokens');
  console.log('3. Or wait for block rewards (if the chain has mining)');
  console.log('');
  console.log('The address with ~100M LXON is:');
  console.log('0x098Ae030804120Def93880a303788d24dc600d00');
  console.log('');
  console.log('Do you have access to this address or the owner private key?');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
