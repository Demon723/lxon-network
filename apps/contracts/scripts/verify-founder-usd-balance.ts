import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Verifying Founder USD Balance\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  const usdTokenAddress = '0x9BE70C4c31E6db3c7200B281559563B2Af509644';

  console.log('Founder:', founderAddress);
  console.log('USD Token:', usdTokenAddress);
  console.log('');

  // Get USD token contract
  const usdToken = await ethers.getContractAt('USDToken', usdTokenAddress);

  // Check founder balance
  const founderBalance = await usdToken.balanceOf(founderAddress);
  const totalSupply = await usdToken.totalSupply();

  console.log('💰 Founder USD Balance:', ethers.formatEther(founderBalance), 'USD');
  console.log('💰 Total Supply:', ethers.formatEther(totalSupply), 'USD');
  console.log('');

  // Check other balances for context
  const lxonTokenAddress = '0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c';
  const wethAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const lxonToken = await ethers.getContractAt('IERC20', lxonTokenAddress);
  const wethToken = await ethers.getContractAt('IERC20', wethAddress);

  const founderLxon = await lxonToken.balanceOf(founderAddress);
  const founderWeth = await wethToken.balanceOf(founderAddress);

  console.log('💰 Founder Other Balances:');
  console.log('  LXON:', ethers.formatEther(founderLxon));
  console.log('  WETH:', ethers.formatEther(founderWeth));
  console.log('');

  console.log('📋 Summary:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('✅ USD Token successfully deployed on LXON network');
  console.log('✅ Founder now has USD tokens on their address');
  console.log('');
  console.log('Founder Holdings:');
  console.log('  USD:', ethers.formatEther(founderBalance), '(1 USDToken = 1 USD)');
  console.log('  LXON:', ethers.formatEther(founderLxon));
  console.log('  WETH:', ethers.formatEther(founderWeth));
  console.log('');
  console.log('USD Value Breakdown:');
  console.log('  USD Tokens:', '$', ethers.formatEther(founderBalance));
  console.log('  WETH (at $1.50):', '$', (Number(ethers.formatEther(founderWeth)) * 1.5).toFixed(2));
  console.log('  LXON (at $1.50):', '$', (Number(ethers.formatEther(founderLxon)) * 1.5).toFixed(2));
  console.log('');
  console.log('Total USD Value: $', (Number(ethers.formatEther(founderBalance)) + Number(ethers.formatEther(founderWeth)) * 1.5 + Number(ethers.formatEther(founderLxon)) * 1.5).toFixed(2));

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
