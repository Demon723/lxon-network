import { ethers } from 'hardhat';

async function main() {
  console.log('💸 Attempting to Transfer Tokens from Contract...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  // Get token contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check contract balances
  const lxonContractBalance = await lxonToken.balanceOf(lxonAddress);
  const nativeContractBalance = await nativeToken.balanceOf(nativeTokenAddress);
  
  console.log('Contract Balances:');
  console.log('LXON Contract holds:', ethers.formatEther(lxonContractBalance));
  console.log('Native Contract holds:', ethers.formatEther(nativeContractBalance));

  // Try to transfer from contract if it has tokens
  if (nativeContractBalance > 0n) {
    console.log('\n💡 Native Token contract has tokens. Trying to transfer...');
    
    try {
      // Try to see if we can call a function to get tokens
      // This will likely fail without proper permissions, but let's try
      const tx = await nativeToken.transfer(deployer.address, ethers.parseEther('100'));
      console.log('Transaction hash:', tx.hash);
      const receipt = await tx.wait();
      console.log('✅ Transfer successful!');
      console.log('Received:', ethers.formatEther(ethers.parseEther('100')), 'Native tokens');
    } catch (error: any) {
      console.log('❌ Transfer failed:', error.message);
      console.log('Contract likely needs special permissions or functions to distribute tokens');
    }
  }

  // Alternative: Try to mint if deployer has permissions
  console.log('\n🔍 Trying to mint tokens...');
  
  try {
    // Try to call mint function (if it exists)
    const mintTx = await nativeToken.mint(deployer.address, ethers.parseEther('100'));
    console.log('Mint transaction hash:', mintTx.hash);
    const receipt = await mintTx.wait();
    console.log('✅ Mint successful!');
  } catch (error: any) {
    console.log('❌ Mint failed:', error.message);
    console.log('No mint function or no permission');
  }

  // Check final balances
  const finalLXON = await lxonToken.balanceOf(deployer.address);
  const finalNative = await nativeToken.balanceOf(deployer.address);
  
  console.log('\nFinal Balances:');
  console.log('LXON:', ethers.formatEther(finalLXON));
  console.log('Native:', ethers.formatEther(finalNative));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
