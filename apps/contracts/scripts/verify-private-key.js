const { ethers } = require("ethers");
require("dotenv").config();

const PRIVATE_KEY = process.env.YOUR_WALLET_PRIVATE_KEY;
const EXPECTED_ADDRESS = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

async function main() {
  console.log("=== Verify Private Key Matches Address ===\n");

  if (!PRIVATE_KEY) {
    console.log("❌ No private key found");
    return;
  }

  const wallet = new ethers.Wallet(PRIVATE_KEY);
  console.log("Derived Address:", wallet.address);
  console.log("Expected Address:", EXPECTED_ADDRESS);
  console.log();

  if (wallet.address.toLowerCase() === EXPECTED_ADDRESS.toLowerCase()) {
    console.log("✅ Private key matches the address!");
    console.log("You can now access the 1 billion LXON.");
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
