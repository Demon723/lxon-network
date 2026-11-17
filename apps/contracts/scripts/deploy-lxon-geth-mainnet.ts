import { ethers } from 'hardhat';
import { writeFileSync, mkdirSync } from 'fs';

async function main() {
  console.log('Deploying LXON Contracts to Geth v1.10.26 Mainnet (Chain ID 724)...');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Account balance:', ethers.formatEther(balance), 'ETH');

  // Deploy LXON Native Token
  console.log('\nDeploying LXONNativeToken...');
  const LXONNativeToken = await ethers.getContractFactory('LXONNativeToken');
  const token = await LXONNativeToken.deploy(ethers.ZeroAddress); // No multi-sig for now
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log('LXONNativeToken deployed to:', tokenAddress);

  // Deploy Wrapped LXON
  console.log('\nDeploying WrappedLXON...');
  const WrappedLXON = await ethers.getContractFactory('WrappedLXON');
  const wrapped = await WrappedLXON.deploy();
  await wrapped.waitForDeployment();
  const wrappedAddress = await wrapped.getAddress();
  console.log('WrappedLXON deployed to:', wrappedAddress);

  // Verify deployments
  console.log('\nVerifying deployments...');
  
  const tokenName = await token.name();
  const tokenSymbol = await token.symbol();
  const tokenDecimals = await token.decimals();
  const tokenTotalSupply = await token.totalSupply();
  
  console.log('LXONNativeToken:');
  console.log('  Name:', tokenName);
  console.log('  Symbol:', tokenSymbol);
  console.log('  Decimals:', tokenDecimals);
  console.log('  Total Supply:', ethers.formatEther(tokenTotalSupply));
  
  const wrappedName = await wrapped.name();
  const wrappedSymbol = await wrapped.symbol();
  const wrappedDecimals = await wrapped.decimals();
  
  console.log('\nWrappedLXON:');
  console.log('  Name:', wrappedName);
  console.log('  Symbol:', wrappedSymbol);
  console.log('  Decimals:', wrappedDecimals);

  const network = await ethers.provider.getNetwork();
  const deployment = {
    network: network.name,
    chainId: Number(network.chainId),
    deployer: deployer.address,
    contracts: {
      LXONNativeToken: tokenAddress,
      WrappedLXON: wrappedAddress,
    },
    deployedAt: new Date().toISOString(),
  };

  const dir = './deployments';
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${dir}/724-geth-mainnet.json`, JSON.stringify(deployment, null, 2));

  console.log('\n✅ Deployment complete!');
  console.log('Deployment info saved to deployments/724-geth-mainnet.json');
  console.log('\nContract Addresses:');
  console.log('  LXONNativeToken:', tokenAddress);
  console.log('  WrappedLXON:', wrappedAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
