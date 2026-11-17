import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Token Minting Permissions...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('LXON Token:', lxonAddress);
  console.log('Native Token:', nativeTokenAddress);

  // Get token contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check current balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);
  
  console.log('\nCurrent Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native:', ethers.formatEther(nativeBalance));

  // Try to check if deployer is owner/minter
  console.log('\n🔍 Checking for mint permissions...');
  
  try {
    // Try to call owner function if it exists
    const ownerCall = await lxonToken.owner.staticCall();
    console.log('LXON Owner:', ownerCall);
    console.log('Is Deployer Owner:', ownerCall.toLowerCase() === deployer.address.toLowerCase() ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('LXON: No owner function or cannot check');
  }

  try {
    const ownerCall = await nativeToken.owner.staticCall();
    console.log('Native Owner:', ownerCall);
    console.log('Is Deployer Owner:', ownerCall.toLowerCase() === deployer.address.toLowerCase() ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('Native: No owner function or cannot check');
  }

  // Check total supply
  try {
    const lxonSupply = await lxonToken.totalSupply();
    console.log('\nLXON Total Supply:', ethers.formatEther(lxonSupply));
  } catch (e) {
    console.log('Cannot get LXON total supply');
  }

  try {
    const nativeSupply = await nativeToken.totalSupply();
    console.log('Native Total Supply:', ethers.formatEther(nativeSupply));
  } catch (e) {
    console.log('Cannot get Native total supply');
  }

  console.log('\n💡 Options to acquire tokens:');
  console.log('1. If you are owner: Use mint function to create tokens');
  console.log('2. Transfer from another address that has tokens');
  console.log('3. Buy on exchanges (if listed)');
  console.log('4. Participate in token sales/airdrops');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
