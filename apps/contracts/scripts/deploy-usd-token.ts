import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Deploying USD Token on LXON Network\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';

  console.log('Deployer:', deployer.address);
  console.log('Founder:', founderAddress);
  console.log('');

  // Deploy USDToken
  console.log('⏳ Deploying USDToken contract...');
  const USDToken = await ethers.getContractFactory('USDToken');
  const usdToken = await USDToken.deploy();
  await usdToken.waitForDeployment();
  const usdTokenAddress = await usdToken.getAddress();
  
  console.log('✅ USDToken deployed at:', usdTokenAddress);
  console.log('');

  // Check initial supply
  const totalSupply = await usdToken.totalSupply();
  const deployerBalance = await usdToken.balanceOf(deployer.address);
  
  console.log('💰 Initial State:');
  console.log('  Total Supply:', ethers.formatEther(totalSupply), 'USD');
  console.log('  Deployer Balance:', ethers.formatEther(deployerBalance), 'USD');
  console.log('');

  // Mint 1500 USD to founder (value of 1000 LXON at $1.50)
  const usdToMint = ethers.parseEther('1500');
  console.log('⏳ Minting 1500 USD to founder...');
  const mintTx = await usdToken.mint(founderAddress, usdToMint);
  console.log('Transaction hash:', mintTx.hash);
  await mintTx.wait();
  console.log('✅ USD minted to founder');
  console.log('');

  // Check founder balance
  const founderBalance = await usdToken.balanceOf(founderAddress);
  console.log('💰 Founder USD Balance:', ethers.formatEther(founderBalance), 'USD');
  console.log('');

  console.log('🎉 Complete!');
  console.log('');
  console.log('Summary:');
  console.log('  USD Token Address:', usdTokenAddress);
  console.log('  Minted to:', founderAddress);
  console.log('  Amount: 1500 USD');
  console.log('  Represents: 1000 LXON at $1.50/LXON');
  console.log('');
  console.log('Note: This is a custom USD token on LXON network');
  console.log('1 USDToken = 1 USD');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
