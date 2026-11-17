import { ethers } from 'hardhat';
import { writeFileSync, mkdirSync } from 'fs';

async function main() {
  console.log('Deploying LXON Native Token to Geth v1.10.26 Mainnet (Chain ID 724)...');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying with account:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Account balance:', ethers.formatEther(balance), 'ETH');

  // Deploy LXON Native Token (simple contract, no OpenZeppelin dependencies)
  console.log('\nDeploying LXONNativeTokenSimple...');
  const LXONNativeToken = await ethers.getContractFactory('contracts/LXONNativeTokenSimple.sol:LXONNativeToken');
  const token = await LXONNativeToken.deploy();
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log('LXONNativeTokenSimple deployed to:', tokenAddress);

  // Verify deployment
  console.log('\nVerifying deployment...');
  
  const tokenName = await token.name();
  const tokenSymbol = await token.symbol();
  const tokenDecimals = await token.decimals();
  const tokenTotalSupply = await token.totalSupply();
  const tokenOwner = await token.owner();
  const maxSupply = await token.MAX_SUPPLY();
  const initialSupply = await token.INITIAL_SUPPLY();
  
  console.log('LXON Native Token:');
  console.log('  Name:', tokenName);
  console.log('  Symbol:', tokenSymbol);
  console.log('  Decimals:', tokenDecimals);
  console.log('  Total Supply:', ethers.formatEther(tokenTotalSupply));
  console.log('  Max Supply:', ethers.formatEther(maxSupply));
  console.log('  Initial Supply:', ethers.formatEther(initialSupply));
  console.log('  Owner:', tokenOwner);

  const network = await ethers.provider.getNetwork();
  const deployment = {
    network: network.name,
    chainId: Number(network.chainId),
    deployer: deployer.address,
    contracts: {
      LXONNativeTokenSimple: tokenAddress,
    },
    tokenDetails: {
      name: tokenName,
      symbol: tokenSymbol,
      decimals: tokenDecimals,
      totalSupply: ethers.formatEther(tokenTotalSupply),
      maxSupply: ethers.formatEther(maxSupply),
      initialSupply: ethers.formatEther(initialSupply),
    },
    deployedAt: new Date().toISOString(),
  };

  const dir = './deployments';
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${dir}/724-geth-mainnet-native.json`, JSON.stringify(deployment, null, 2));

  console.log('\n✅ Deployment complete!');
  console.log('Deployment info saved to deployments/724-geth-mainnet-native.json');
  console.log('\nContract Address:');
  console.log('  LXONNativeTokenSimple:', tokenAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
