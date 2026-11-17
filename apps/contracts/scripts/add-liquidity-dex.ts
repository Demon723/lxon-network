import { ethers } from 'hardhat';

async function main() {
  console.log('💧 Adding Liquidity to DEX Pair...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Account:', deployer.address);

  // Load deployment info
  const fs = require('fs');
  const deploymentPath = './deployments/dex-factory-724.json';
  const deploymentInfo = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));

  const router = await ethers.getContractAt('UniversalRouter', deploymentInfo.contracts.UniversalRouter);

  // Token addresses
  const lxonAddress = process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  const nativeTokenAddress = process.env.WETH_ADDRESS || '0x007696cdF0Bf860823126D72C8e3D52448B5285E';

  console.log('LXON:', lxonAddress);
  console.log('Native Token:', nativeTokenAddress);

  // Get token contracts
  const lxonToken = await ethers.getContractAt('IERC20', lxonAddress);
  const nativeToken = await ethers.getContractAt('IERC20', nativeTokenAddress);

  // Check balances
  const lxonBalance = await lxonToken.balanceOf(deployer.address);
  const nativeBalance = await nativeToken.balanceOf(deployer.address);

  console.log('\n💰 Current Balances:');
  console.log('LXON:', ethers.formatEther(lxonBalance));
  console.log('Native Token:', ethers.formatEther(nativeBalance));

  if (lxonBalance === 0n || nativeBalance === 0n) {
    console.error('\n❌ Insufficient token balances for liquidity!');
    console.log('You need both LXON and Native Token to add liquidity.');
    process.exit(1);
  }

  // Add liquidity (use 10% of balances for safety)
  const amountLXON = lxonBalance / 10n;
  const amountNative = nativeBalance / 10n;

  console.log('\n💧 Adding Liquidity:');
  console.log('LXON amount:', ethers.formatEther(amountLXON));
  console.log('Native Token amount:', ethers.formatEther(amountNative));

  // Approve router to spend tokens
  console.log('\n⏳ Approving tokens...');
  await lxonToken.approve(await router.getAddress(), amountLXON);
  await nativeToken.approve(await router.getAddress(), amountNative);
  console.log('✅ Tokens approved');

  // Add liquidity
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60; // 20 minutes
  console.log('\n⏳ Adding liquidity to pair...');

  const tx = await router.addLiquidity(
    lxonAddress,
    nativeTokenAddress,
    amountLXON,
    amountNative,
    amountLXON * 95n / 100n, // 5% slippage tolerance
    amountNative * 95n / 100n,
    deployer.address,
    deadline
  );

  console.log('Transaction hash:', tx.hash);
  const receipt = await tx.wait();
  console.log('✅ Liquidity added!');
  console.log('Gas used:', receipt.gasUsed.toString());

  // Check LP token balance
  const pairAddress = await router.getPair(lxonAddress, nativeTokenAddress);
  const pair = await ethers.getContractAt('Pair', pairAddress);
  const lpBalance = await pair.balanceOf(deployer.address);
  console.log('LP Tokens received:', ethers.formatEther(lpBalance));

  // Check new reserves
  const [reserve0, reserve1] = await pair.getReserves();
  console.log('\n📊 New Reserves:');
  console.log('LXON:', ethers.formatEther(reserve0));
  console.log('Native Token:', ethers.formatEther(reserve1));

  console.log('\n🎉 Liquidity added successfully!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  Pair: ${pairAddress}`);
  console.log(`  LP Tokens: ${ethers.formatEther(lpBalance)}`);
  console.log(`  LXON Reserve: ${ethers.formatEther(reserve0)}`);
  console.log(`  Native Reserve: ${ethers.formatEther(reserve1)}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
