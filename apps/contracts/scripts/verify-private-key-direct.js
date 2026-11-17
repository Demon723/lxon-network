const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Read .env file directly
const envPath = path.join(__dirname, '..', '.env');
const envContent = fs.readFileSync(envPath, 'utf8');

// Parse the private key
const lines = envContent.split('\n');
let PRIVATE_KEY = null;
for (const line of lines) {
  if (line.startsWith('YOUR_WALLET_PRIVATE_KEY=')) {
    PRIVATE_KEY = line.split('=')[1].trim();
    break;
  }
}

console.log("Extracted key:", PRIVATE_KEY ? PRIVATE_KEY.substring(0, 10) + "..." : "null");
const EXPECTED_ADDRESS = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

async function main() {
  console.log("=== Verify Private Key Matches Address ===\n");

  if (!PRIVATE_KEY) {
    console.log("❌ No private key found in .env");
    return;
  }

  console.log("Private Key found:", PRIVATE_KEY.substring(0, 10) + "...");
  console.log();

  const wallet = new ethers.Wallet(PRIVATE_KEY);
  console.log("Derived Address:", wallet.address);
  console.log("Expected Address:", EXPECTED_ADDRESS);
  console.log();

  if (wallet.address.toLowerCase() === EXPECTED_ADDRESS.toLowerCase()) {
    console.log("✅ SUCCESS! Private key matches the address!");
    console.log();
    console.log("You can now access the 1 billion LXON.");
    console.log("This private key can be imported into MetaMask.");
  } else {
    console.log("❌ Private key does NOT match the address!");
    console.log("This private key is for a different wallet.");
    console.log("The 1 billion LXON are still inaccessible.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
