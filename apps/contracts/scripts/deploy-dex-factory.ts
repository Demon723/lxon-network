import { ethers } from 'hardhat';

async function main() {
  console.log('🚀 Deploying DEX Factory and Universal Router...\n');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);
  console.log('Account balance:', ethers.formatEther(await ethers.provider.getBalance(deployer.address)), 'ETH');

  // Deploy DEXFactory
  console.log('\n📦 Deploying DEXFactory...');
  const DEXFactory = await ethers.deployContract('DEXFactory', [deployer.address]);
  await DEXFactory.waitForDeployment();
  const factoryAddress = await DEXFactory.getAddress();
  console.log('✅ DEXFactory deployed to:', factoryAddress);

  // Deploy UniversalRouter
  console.log('\n📦 Deploying UniversalRouter...');
  // Use WETH address from .env or native token address for LXON blockchain
  const wethAddress = process.env.WETH_ADDRESS || process.env.LXON_ADDRESS || '0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E';
  console.log('Native token address:', wethAddress);

  const UniversalRouter = await ethers.deployContract('UniversalRouter', [factoryAddress, wethAddress]);
  await UniversalRouter.waitForDeployment();
  const routerAddress = await UniversalRouter.getAddress();
  console.log('✅ UniversalRouter deployed to:', routerAddress);

  // Save deployment info
  const network = await ethers.provider.getNetwork();
  const deploymentInfo = {
    network: network.name,
    chainId: Number(network.chainId),
    deployer: deployer.address,
    contracts: {
      DEXFactory: factoryAddress,
      UniversalRouter: routerAddress,
      WETH: wethAddress,
    },
    deployedAt: new Date().toISOString(),
  };

  const fs = require('fs');
  const dir = './deployments';
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${dir}/dex-factory-${Number(network.chainId)}.json`, JSON.stringify(deploymentInfo, null, 2));

  console.log('\n🎉 Deployment Complete!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Summary:');
  console.log(`  DEXFactory: ${factoryAddress}`);
  console.log(`  UniversalRouter: ${routerAddress}`);
  console.log(`  WETH: ${wethAddress}`);
  console.log(`  Deployer: ${deployer.address}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('\n💾 Deployment info saved to deployments/');

  console.log('\n📝 Next Steps:');
  console.log('  1. Create trading pairs using UniversalRouter.createPair()');
  console.log('  2. Add liquidity to pairs using UniversalRouter.addLiquidity()');
  console.log('  3. Start swapping tokens using UniversalRouter.swapExactTokensForTokens()');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
