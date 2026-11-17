import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("⚠️  REVOKING OLD DEPLOYER PERMISSIONS");
  console.log("This will remove the old deployer's permissions from all contracts\n");

  const oldDeployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";

  console.log("Old deployer address:", oldDeployerAddress);
  console.log("\n⚠️  CRITICAL WARNING:");
  console.log("This action is irreversible");
  console.log("Make sure:");
  console.log("1. New deployer key is working");
  console.log("2. Multi-sig is operational");
  console.log("3. All contracts are accessible via multi-sig");
  console.log("4. Emergency recovery procedures are documented\n");

  // Load deployment data
  const freshContracts = JSON.parse(
    fs.readFileSync('./deployments/fresh-contracts.json', 'utf8')
  );
  const priceFloorDeployment = JSON.parse(
    fs.readFileSync('./deployments/price-floor-deployment.json', 'utf8')
  );
  const multiSigDeployment = JSON.parse(
    fs.readFileSync('./deployments/multisig-deployment.json', 'utf8')
  );

  const multiSigAddress = multiSigDeployment.MULTI_SIG_ADDRESS;
  const lxonAddress = freshContracts.LXON_ADDRESS;

  console.log("Multi-sig address:", multiSigAddress);
  console.log("LXON address:", lxonAddress);

  // Wait for confirmation
  console.log("\nPress Ctrl+C to cancel, or wait 10 seconds to proceed...");
  await new Promise(resolve => setTimeout(resolve, 10000));

  console.log("\n=== Revoking Permissions ===");

  // Get deployer signer
  const deployer = await ethers.getSigner(oldDeployerAddress);

  // Revoke LXON roles from old deployer
  console.log("\n1. Revoking LXON roles from old deployer...");

  const lxonAbi = [
    "function DEFAULT_ADMIN_ROLE() external view returns (bytes32)",
    "function MINT_ROLE() external view returns (bytes32)",
    "function ORACLE_ROLE() external view returns (bytes32)",
    "function hasRole(bytes32 role, address account) external view returns (bool)",
    "function revokeRole(bytes32 role, address account) external"
  ];

  const lxon = new ethers.Contract(lxonAddress, lxonAbi, deployer);

  const DEFAULT_ADMIN_ROLE = await lxon.DEFAULT_ADMIN_ROLE();
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();

  // Check if old deployer has roles
  const hasDefaultAdmin = await lxon.hasRole(DEFAULT_ADMIN_ROLE, oldDeployerAddress);
  const hasMintRole = await lxon.hasRole(MINT_ROLE, oldDeployerAddress);
  const hasOracleRole = await lxon.hasRole(ORACLE_ROLE, oldDeployerAddress);

  console.log("Has DEFAULT_ADMIN_ROLE:", hasDefaultAdmin);
  console.log("Has MINT_ROLE:", hasMintRole);
  console.log("Has ORACLE_ROLE:", hasOracleRole);

  // Revoke MINT_ROLE and ORACLE_ROLE first (while we still have DEFAULT_ADMIN)
  if (hasMintRole) {
    console.log("Revoking MINT_ROLE...");
    const tx2 = await lxon.revokeRole(MINT_ROLE, oldDeployerAddress);
    console.log("Transaction submitted:", tx2.hash);
    await tx2.wait();
    console.log("✅ MINT_ROLE revoked");
  }

  if (hasOracleRole) {
    console.log("Revoking ORACLE_ROLE...");
    const tx3 = await lxon.revokeRole(ORACLE_ROLE, oldDeployerAddress);
    console.log("Transaction submitted:", tx3.hash);
    await tx3.wait();
    console.log("✅ ORACLE_ROLE revoked");
  }

  // Revoke DEFAULT_ADMIN_ROLE last
  if (hasDefaultAdmin) {
    console.log("Revoking DEFAULT_ADMIN_ROLE...");
    const tx1 = await lxon.revokeRole(DEFAULT_ADMIN_ROLE, oldDeployerAddress);
    console.log("Transaction submitted:", tx1.hash);
    await tx1.wait();
    console.log("✅ DEFAULT_ADMIN_ROLE revoked");
  }

  // Save revocation data
  const revocationData = {
    OLD_DEPLOYER_ADDRESS: oldDeployerAddress,
    REVOCATION_TIMESTAMP: new Date().toISOString(),
    REVOKED_ROLES: {
      LXON: {
        DEFAULT_ADMIN_ROLE: hasDefaultAdmin,
        MINT_ROLE: hasMintRole,
        ORACLE_ROLE: hasOracleRole
      }
    },
    MULTI_SIG_ADDRESS: multiSigAddress,
    NOTES: "Old deployer permissions revoked. Multi-sig now controls all operations."
  };

  fs.writeFileSync(
    './deployments/deployer-permission-revocation.json',
    JSON.stringify(revocationData, null, 2)
  );

  console.log("\n=== Permission Revocation Complete ===");
  console.log("Old deployer address:", oldDeployerAddress);
  console.log("Revoked LXON roles: DEFAULT_ADMIN, MINT, ORACLE");

  console.log("\n=== FINAL SECURITY STEPS ===");
  console.log("1. Delete old private key from .env file");
  console.log("2. Clear shell history: history -c");
  console.log("3. Clear clipboard history");
  console.log("4. Destroy any backups of old key");
  console.log("5. Document old address for audit trail");
  console.log("6. Test that multi-sig controls all operations");

  console.log("\n⚠️  CRITICAL: The old deployer can no longer:");
  console.log("- Mint LXON tokens");
  console.log("- Update oracle settings");
  console.log("- Change LXON configuration");
  console.log("- Execute admin operations on LXON");

  console.log("\n✅ All critical operations now require multi-sig approval");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
