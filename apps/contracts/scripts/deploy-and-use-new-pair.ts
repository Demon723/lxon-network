import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Deploying New Pair Contract Directly and Adding Liquidity\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const [deployer] = await ethers.getSigners();
  const targetAddress = '0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27';
  
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('Deployer:', deployer.address);
  console.log('LXON Token:', lxonTokenAddress);
  console.log('WETH Token:', wethAddress);
  console.log('');

  // Get token contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(targetAddress);
  const wethBalance = await wethToken.balanceOf(targetAddress);

  console.log('💰 Current Balances:');
  console.log('  LXON:', ethers.formatEther(lxonBalance));
  console.log('  WETH:', ethers.formatEther(wethBalance));
  console.log('');

  // Deploy new Pair contract
  console.log('⏳ Deploying new Pair contract (MINIMUM_LIQUIDITY = 1)...');
  const Pair = await ethers.getContractFactory('Pair');
  const pair = await Pair.deploy(lxonTokenAddress, wethAddress);
  await pair.waitForDeployment();
  const pairAddress = await pair.getAddress();
  
  console.log('✅ Pair deployed at:', pairAddress);
  console.log('');

  // Transfer tokens to pair
  const lxonAmount = ethers.parseEther('1000');
  const wethAmount = ethers.parseEther('1500');

  console.log('⏳ Transferring tokens to pair...');
  console.log('  LXON:', ethers.formatEther(lxonAmount));
  console.log('  WETH:', ethers.formatEther(wethAmount));
  console.log('');

  const lxonTransfer = await lxonToken.transfer(pairAddress, lxonAmount);
  await lxonTransfer.wait();
  console.log('✅ LXON transferred');

  const wethTransfer = await wethToken.transfer(pairAddress, wethAmount);
  await wethTransfer.wait();
  console.log('✅ WETH transferred');
  console.log('');

  // Mint LP tokens
  console.log('⏳ Minting LP tokens...');
  try {
    const mintTx = await pair.mint(targetAddress);
    console.log('Transaction hash:', mintTx.hash);
    await mintTx.wait();
    console.log('✅ LP tokens minted successfully!');
    console.log('');

    // Check reserves
    const [reserve0, reserve1] = await pair.getReserves();
    console.log('📊 Reserves:');
    console.log('  Reserve 0:', ethers.formatEther(reserve0));
    console.log('  Reserve 1:', ethers.formatEther(reserve1));
    console.log('');

    // Check LP token balance
    const lpBalance = await pair.balanceOf(targetAddress);
    console.log('💰 LP Tokens:', ethers.formatEther(lpBalance));
    console.log('');

    console.log('🎉 Liquidity added successfully with new Pair contract!');
    console.log('');
    console.log('Pair Address:', pairAddress);
    console.log('This pair can now be used for swaps');

  } catch (error: any) {
    console.log('❌ Error minting LP tokens:', error.message);
    console.log('');
    console.log('Try checking pair balances after transfers...');
    
    const pairLxon = await lxonToken.balanceOf(pairAddress);
    const pairWeth = await wethToken.balanceOf(pairAddress);
    console.log('Pair LXON balance:', ethers.formatEther(pairLxon));
    console.log('Pair WETH balance:', ethers.formatEther(pairWeth));
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
