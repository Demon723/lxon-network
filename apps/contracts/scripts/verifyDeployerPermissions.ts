import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("Verifying deployer permissions...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";

  console.log("Deployer address:", deployerAddress);

  // Load deployment data
  const freshContracts = JSON.parse(
    fs.readFileSync('./deployments/fresh-contracts.json', 'utf8')
  );

  const lxonAddress = freshContracts.LXON_ADDRESS;
  console.log("LXON address:", lxonAddress);

  // Get deployer signer
  const deployer = await ethers.getSigner(deployerAddress);

  // LXON ABI
  const lxonAbi = [
    "function DEFAULT_ADMIN_ROLE() external view returns (bytes32)",
    "function MINT_ROLE() external view returns (bytes32)",
    "function ORACLE_ROLE() external view returns (bytes32)",
    "function hasRole(bytes32 role, address account) external view returns (bool)"
  ];

  // Connect to LXON
  const lxon = new ethers.Contract(lxonAddress, lxonAbi, deployer);

  // Get role hashes
  const DEFAULT_ADMIN_ROLE = await lxon.DEFAULT_ADMIN_ROLE();
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();

  // Check deployer's roles
  const hasDefaultAdmin = await lxon.hasRole(DEFAULT_ADMIN_ROLE, deployerAddress);
  const hasMintRole = await lxon.hasRole(MINT_ROLE, deployerAddress);
  const hasOracleRole = await lxon.hasRole(ORACLE_ROLE, deployerAddress);

  console.log("\n=== Deployer Permission Status ===");
  console.log("DEFAULT_ADMIN_ROLE:", hasDefaultAdmin ? "❌ HAS ACCESS" : "✅ REVOKED");
  console.log("MINT_ROLE:", hasMintRole ? "❌ HAS ACCESS" : "✅ REVOKED");
  console.log("ORACLE_ROLE:", hasOracleRole ? "❌ HAS ACCESS" : "✅ REVOKED");

  console.log("\n=== Security Assessment ===");
  if (!hasDefaultAdmin && !hasMintRole && !hasOracleRole) {
    console.log("✅ ALL ROLES REVOKED - Deployer has no admin access");
    console.log("✅ Safe to proceed with key rotation");
  } else {
    console.log("⚠️  SOME ROLES STILL ACTIVE - Not safe for key rotation yet");
    console.log("Please complete hardware wallet confirmation first");
  }

  console.log("\n=== What the deployer can still do ===");
  if (hasDefaultAdmin) {
    console.log("❌ Grant/revoke roles");
    console.log("❌ Change contract configuration");
  }
  if (hasMintRole) {
    console.log("❌ Mint LXON tokens");
  }
  if (hasOracleRole) {
    console.log("❌ Update oracle settings");
  }

  if (!hasDefaultAdmin && !hasMintRole && !hasOracleRole) {
    console.log("✅ None - Deployer has no admin capabilities");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
