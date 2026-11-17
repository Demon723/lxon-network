import { ethers } from 'hardhat';

async function main() {
  console.log('🔍 Checking for USD Stablecoins on LXON Network\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const founderAddress = '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3';
  
  // Common USDC/USDT contract addresses on various networks
  // These are typically deployed by Circle or Tether
  const potentialUsdcAddresses = [
    '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // Ethereum Mainnet USDC
    '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d', // BSC USDC
    '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', // Polygon USDC
    '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75', // Fantom USDC
    '0xB97EF59Ef84EcB2569794499Ee8FCB3B13C5eb43', // Arbitrum USDC
  ];

  const potentialUsdtAddresses = [
    '0xdAC17F958D2ee523a2206206994597C13D831ec7', // Ethereum Mainnet USDT
    '0x55d398326f99059fF775485246999027B3197955', // BSC USDT
    '0xc2132D05D31c914a87C6611C10748AEb04B58e8F', // Polygon USDT
  ];

  console.log('Checking for USDC contracts...');
  let usdcFound = false;
  let usdcAddress = ethers.ZeroAddress;

  for (const addr of potentialUsdcAddresses) {
    try {
      const code = await ethers.provider.getCode(addr);
      if (code !== '0x') {
        console.log('✅ Found contract at:', addr);
        try {
          const token = await ethers.getContractAt('IERC20', addr);
          const name = await token.name();
          const symbol = await token.symbol();
          const decimals = await token.decimals();
          const balance = await token.balanceOf(founderAddress);
          
          console.log('  Name:', name);
          console.log('  Symbol:', symbol);
          console.log('  Decimals:', decimals);
          console.log('  Founder Balance:', ethers.formatUnits(balance, decimals));
          
          if (symbol === 'USDC' || symbol === 'USD Coin') {
            usdcFound = true;
            usdcAddress = addr;
          }
        } catch (e: any) {
          console.log('  Could not read token info:', e.message);
        }
      }
    } catch (e: any) {
      // Address doesn't exist, continue
    }
  }

  console.log('');
  console.log('Checking for USDT contracts...');
  let usdtFound = false;
  let usdtAddress = ethers.ZeroAddress;

  for (const addr of potentialUsdtAddresses) {
    try {
      const code = await ethers.provider.getCode(addr);
      if (code !== '0x') {
        console.log('✅ Found contract at:', addr);
        try {
          const token = await ethers.getContractAt('IERC20', addr);
          const name = await token.name();
          const symbol = await token.symbol();
          const decimals = await token.decimals();
          const balance = await token.balanceOf(founderAddress);
          
          console.log('  Name:', name);
          console.log('  Symbol:', symbol);
          console.log('  Decimals:', decimals);
          console.log('  Founder Balance:', ethers.formatUnits(balance, decimals));
          
          if (symbol === 'USDT' || symbol === 'Tether USD') {
            usdtFound = true;
            usdtAddress = addr;
          }
        } catch (e: any) {
          console.log('  Could not read token info:', e.message);
        }
      }
    } catch (e: any) {
      // Address doesn't exist, continue
    }
  }

  console.log('');
  console.log('📋 Summary:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('USDC Found:', usdcFound ? '✅ Yes' : '❌ No');
  if (usdcFound) console.log('  Address:', usdcAddress);
  console.log('');
  console.log('USDT Found:', usdtFound ? '✅ Yes' : '❌ No');
  if (usdtFound) console.log('  Address:', usdtAddress);
  console.log('');

  if (!usdcFound && !usdtFound) {
    console.log('⚠️ No USD stablecoin found on LXON network');
    console.log('');
    console.log('💡 Options:');
    console.log('  1. Deploy a USDC/USDT contract on LXON network');
    console.log('  2. Create a custom USD token on LXON network');
    console.log('  3. Bridge USDC/USDT from another network to LXON');
    console.log('  4. Continue using WETH as USD equivalent (at $1.50/WETH)');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
