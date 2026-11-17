import { ethers } from 'hardhat';
import { writeFileSync, mkdirSync } from 'fs';

async function main() {
  console.log('Deploying WrappedLXON to Geth v1.10.26 Mainnet (Chain ID 724)...');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Account balance:', ethers.formatEther(balance), 'ETH');

  // Deploy Wrapped LXON (simple contract, no OpenZeppelin dependencies)
  console.log('\nDeploying WrappedLXON...');
  const WrappedLXON = await ethers.getContractFactory('WrappedLXON');
  const wrapped = await WrappedLXON.deploy();
  await wrapped.waitForDeployment();
  const wrappedAddress = await wrapped.getAddress();
  console.log('WrappedLXON deployed to:', wrappedAddress);

  // Verify deployment
  console.log('\nVerifying deployment...');
  
  const wrappedName = await wrapped.name();
  const wrappedSymbol = await wrapped.symbol();
  const wrappedDecimals = await wrapped.decimals();
  const admin = await wrapped.admin();
  
  console.log('WrappedLXON:');
  console.log('  Name:', wrappedName);
  console.log('  Symbol:', wrappedSymbol);
  console.log('  Decimals:', wrappedDecimals);
  console.log('  Admin:', admin);

  const network = await ethers.provider.getNetwork();
  const deployment = {
    network: network.name,
    chainId: Number(network.chainId),
    deployer: deployer.address,
    contracts: {
      WrappedLXON: wrappedAddress,
    },
    deployedAt: new Date().toISOString(),
  };

  const dir = './deployments';
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${dir}/724-geth-mainnet-wrapped.json`, JSON.stringify(deployment, null, 2));

  console.log('\n✅ Deployment complete!');
  console.log('Deployment info saved to deployments/724-geth-mainnet-wrapped.json');
  console.log('\nContract Address:');
  console.log('  WrappedLXON:', wrappedAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
