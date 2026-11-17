import { ethers } from "hardhat";

async function main() {
  console.log("=== Checking LXON Network for Pre-funded Accounts ===\n");

  const provider = new ethers.JsonRpcProvider("http://16.171.20.249:8545");
  
  // Standard Hardhat test accounts to check
  const testAccounts = [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
    "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc",
    "0x976EA74026E726554dB657fA54763abd0C3a0aa9",
    "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955",
    "0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f",
    "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720"
  ];

  let fundedAccounts = 0;

  for (const account of testAccounts) {
    try {
      const balance = await provider.getBalance(account);
      if (balance > 0) {
        console.log(`✅ Account ${account}: ${ethers.formatEther(balance)} LXON`);
        fundedAccounts++;
      }
    } catch (error) {
      // Skip errors
    }
  }

  if (fundedAccounts === 0) {
    console.log("❌ No pre-funded test accounts found");
    console.log("\n=== Options ===");
    console.log("1. Fund the deployer account manually");
    console.log("2. Check if there's a faucet for this network");
    console.log("3. Use a different account that has funds");
    console.log("4. Contact LXON team for test funds");
  } else {
    console.log(`\n✅ Found ${fundedAccounts} funded account(s)`);
    console.log("You can use one of these accounts for deployment");
  }

  // Check network info
  console.log("\n=== Network Info ===");
  const network = await provider.getNetwork();
  console.log("Chain ID:", network.chainId);
  const blockNumber = await provider.getBlockNumber();
  console.log("Block Number:", blockNumber);
  
  if (blockNumber === 0) {
    console.log("⚠️ This is a fresh chain (block 0)");
    console.log("You'll need to deploy all contracts from scratch");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });