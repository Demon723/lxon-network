import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking Owner Native Token Balance\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const ownerAddress = '0x098Ae030804120Def93880a303788d24dc600d00';
  const nativeTokenAddress = '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);
  const ownerNativeBalance = await nativeToken.balanceOf(ownerAddress);

  console.log('Owner Address:', ownerAddress);
  console.log('Owner Native Balance:', ethers.formatEther(ownerNativeBalance));
  console.log('');

  if (Number(ethers.formatEther(ownerNativeBalance)) >= 1000) {
    console.log('✅ Owner has sufficient native tokens!');
    console.log('   We can transfer to your address for liquidity');
  } else {
    console.log('❌ Owner also has insufficient native tokens');
    console.log('   Need alternative approach');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
