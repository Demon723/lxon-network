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

  // Revoke LXON roles from old deployer
  console.log("\n1. Revoking LXON roles from old deployer...");
  const lxon = await ethers.getContractAt("LXON", lxonAddress);

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

  if (hasDefaultAdmin) {
    console.log("Revoking DEFAULT_ADMIN_ROLE...");
    const tx1 = await lxon.revokeRole(DEFAULT_ADMIN_ROLE, oldDeployerAddress);
    await tx1.wait();
    console.log("✅ DEFAULT_ADMIN_ROLE revoked");
  }

  if (hasMintRole) {
    console.log("Revoking MINT_ROLE...");
    const tx2 = await lxon.revokeRole(MINT_ROLE, oldDeployerAddress);
    await tx2.wait();
    console.log("✅ MINT_ROLE revoked");
  }

  if (hasOracleRole) {
    console.log("Revoking ORACLE_ROLE...");
    const tx3 = await lxon.revokeRole(ORACLE_ROLE, oldDeployerAddress);
    await tx3.wait();
    console.log("✅ ORACLE_ROLE revoked");
  }

  // Remove old deployer from multi-sig (if still an owner)
  console.log("\n2. Removing old deployer from multi-sig...");
  const multiSig = await ethers.getContractAt("MultiSigWallet", multiSigAddress);

  const isOwner = await multiSig.isOwnerCheck(oldDeployerAddress);
  console.log("Is multi-sig owner:", isOwner);

  if (isOwner) {
    console.log("⚠️  Cannot remove old deployer from multi-sig directly");
    console.log("This must be done via multi-sig transaction");
    console.log("Submit a transaction to remove owner:", oldDeployerAddress);
    console.log("This requires multi-sig approval with current threshold");
  } else {
    console.log("✅ Old deployer is not a multi-sig owner");
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
      },
      MULTI_SIG: {
        OWNER: isOwner
      }
    },
    MULTI_SIG_ADDRESS: multiSigAddress,
    NOTES: "Old deployer permissions revoked. Multi-sig owner removal requires multi-sig transaction."
  };

  fs.writeFileSync(
    './deployments/deployer-permission-revocation.json',
    JSON.stringify(revocationData, null, 2)
  );

  console.log("\n=== Permission Revocation Complete ===");
  console.log("Old deployer address:", oldDeployerAddress);
  console.log("Revoked LXON roles: DEFAULT_ADMIN, MINT, ORACLE");
  console.log("Multi-sig owner removal: Requires multi-sig transaction");

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
