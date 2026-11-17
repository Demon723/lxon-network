import { ethers } from 'hardhat';
import { writeFileSync, mkdirSync } from 'fs';

async function main() {
  console.log('Deploying SimpleWrappedLXON to Geth v1.10.26 Mainnet (Chain ID 724)...');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Account balance:', ethers.formatEther(balance), 'ETH');

  // Deploy Simple Wrapped LXON (no OpenZeppelin dependencies)
  console.log('\nDeploying SimpleWrappedLXON...');
  const SimpleWrappedLXON = await ethers.getContractFactory('SimpleWrappedLXON');
  const wrapped = await SimpleWrappedLXON.deploy();
  await wrapped.waitForDeployment();
  const wrappedAddress = await wrapped.getAddress();
  console.log('SimpleWrappedLXON deployed to:', wrappedAddress);

  // Verify deployment
  console.log('\nVerifying deployment...');
  
  const wrappedName = await wrapped.name();
  const wrappedSymbol = await wrapped.symbol();
  const wrappedDecimals = await wrapped.decimals();
  const admin = await wrapped.admin();
  
  console.log('SimpleWrappedLXON:');
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
      SimpleWrappedLXON: wrappedAddress,
    },
    deployedAt: new Date().toISOString(),
  };

  const dir = './deployments';
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${dir}/724-geth-mainnet-simple-wrapped.json`, JSON.stringify(deployment, null, 2));

  console.log('\n✅ Deployment complete!');
  console.log('Deployment info saved to deployments/724-geth-mainnet-simple-wrapped.json');
  console.log('\nContract Address:');
  console.log('  SimpleWrappedLXON:', wrappedAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
