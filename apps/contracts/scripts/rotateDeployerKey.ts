import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("⚠️  DEPLOYER KEY ROTATION PROCESS");
  console.log("This script will guide you through rotating the deployer private key\n");

  const currentDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";

  console.log("Current deployer address:", currentDeployerAddress);
  console.log("\n⚠️  CRITICAL SECURITY WARNING:");
  console.log("The current deployer private key was exposed during setup");
  console.log("It MUST be rotated before production use\n");

  console.log("Step 1: Generate new secure private key");
  console.log("Use a hardware wallet or secure key generation method");
  console.log("DO NOT use online generators or simple random methods\n");

  console.log("Step 2: Update .env file with new private key");
  console.log("Replace DEPLOYER_PRIVATE_KEY in .env with the new key\n");

  console.log("Step 3: Fund the new address with LXON for gas");
  console.log("Transfer at least 1000 LXON to the new address\n");

  console.log("Step 4: Verify new address has funds");
  console.log("Run: npm run verify:geth");
  console.log("Check that the new address has sufficient balance\n");

  console.log("Step 5: Test transactions with new key");
  console.log("Deploy a test contract or execute a test transaction\n");

  console.log("Step 6: Revoke old deployer's permissions (after testing)");
  console.log("Use revokeDeployerPermissions.ts script\n");

  console.log("Step 7: Securely destroy old private key");
  console.log("Delete from .env, clear from shell history, etc.\n");

  console.log("=== MANUAL STEPS REQUIRED ===");
  console.log("\n1. Generate new private key using hardware wallet:");
  console.log("   - Ledger: Use Ledger Live or Metamask with Ledger");
  console.log("   - Trezor: Use Trezor Suite or Metamask with Trezor");
  console.log("   - Secure key generation: Use openssl or similar tool");

  console.log("\n2. Update .env file:");
  console.log("   DEPLOYER_PRIVATE_KEY=<new_private_key>");
  console.log("   DEPLOYER=<new_address>");

  console.log("\n3. Fund new address:");
  console.log("   Transfer LXON from current deployer to new address");
  console.log("   Use Router or direct transfer");

  console.log("\n4. Verify configuration:");
  console.log("   npm run verify:geth");

  console.log("\n5. Test new key:");
  console.log("   npm run deploy:multisig (test with new key)");

  console.log("\n6. Revoke old permissions:");
  console.log("   npm run revoke:deployer");

  console.log("\n7. Secure old key:");
  console.log("   - Delete from .env file");
  console.log("   - Clear shell history: history -c");
  console.log("   - Clear clipboard history");
  console.log("   - Destroy any backups");

  console.log("\n=== RECOMMENDED HARDWARE WALLET SETUP ===");
  console.log("\nLedger Setup:");
  console.log("1. Install Ledger Live");
  console.log("2. Initialize Ledger device");
  console.log("3. Install Ethereum app on Ledger");
  console.log("4. Connect to Metamask via Ledger");
  console.log("5. Export address and use as new deployer");

  console.log("\nTrezor Setup:");
  console.log("1. Install Trezor Suite");
  console.log("2. Initialize Trezor device");
  console.log("3. Connect to Metamask via Trezor");
  console.log("4. Export address and use as new deployer");

  console.log("\n=== SECURITY BEST PRACTICES ===");
  console.log("1. Never store private keys in plain text");
  console.log("2. Use hardware wallets for production keys");
  console.log("3. Enable multi-factor authentication");
  console.log("4. Regularly rotate keys");
  console.log("5. Maintain secure backups");
  console.log("6. Document recovery procedures");
  console.log("7. Use air-gapped systems for critical operations");

  console.log("\n=== AFTER ROTATION ===");
  console.log("1. Old deployer address: " + currentDeployerAddress);
  console.log("2. New deployer address: <to be filled>");
  console.log("3. Multi-sig owners: <to be updated>");
  console.log("4. Threshold: <to be updated>");

  console.log("\n⚠️  CRITICAL: Save this information securely");
  console.log("Document all addresses and keys in secure storage");
  console.log("Test recovery procedures before emergency use");

  console.log("\nThis script provides guidance only.");
  console.log("Manual execution is required for security reasons.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
