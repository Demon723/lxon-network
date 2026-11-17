import { ethers } from 'hardhat';

async function main() {
  console.log('🎯 GUIDE: How to Get LXON Token Contract Address from MetaMask\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  console.log('STEP 1: In MetaMask');
  console.log('  ✓ You are on LXON Mainnet');
  console.log('  ✓ You can see "LXON" token with 10,000 balance');
  console.log('');

  console.log('STEP 2: Click on the LXON Token');
  console.log('  - Tap on the "LXON" token in your token list');
  console.log('  - This will open the token details page');
  console.log('');

  console.log('STEP 3: Find Contract Address');
  console.log('  - Look for "Contract Address" or "Token Address"');
  console.log('  - It will be a long string starting with "0x..."');
  console.log('  - Example: 0x1234567890abcdef1234567890abcdef12345678');
  console.log('');

  console.log('STEP 4: Copy the Address');
  console.log('  - Tap on the address to copy it');
  console.log('  - Or use the copy button');
  console.log('');

  console.log('STEP 5: Provide it to me');
  console.log('  - Paste the address in the chat');
  console.log('  - I will verify your 10,000 LXON balance');
  console.log('  - Then proceed with DEX operations');
  console.log('');

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🔍 WHAT WE WILL DO ONCE WE HAVE THE ADDRESS:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. Verify your 10,000 LXON balance on the correct contract');
  console.log('2. Check if the token is compatible with our DEX');
  console.log('3. Add liquidity with your 10,000 LXON');
  console.log('4. Execute swap: 1000 LXON → USD ($1500)');
  console.log('5. Send USD to founder: 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3');
  console.log('6. Complete your original goal!');
  console.log('');

  console.log('⏱️  ESTIMATED TIME: 5-10 minutes after providing address');
  console.log('');

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📋 PLEASE PROVIDE:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('The LXON token contract address from MetaMask');
  console.log('(starts with 0x and is 42 characters long)');
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
