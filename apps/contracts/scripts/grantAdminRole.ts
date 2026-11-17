import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("Granting ADMIN_ROLE to deployer on multi-sig...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";

  console.log("Deployer address:", deployerAddress);

  // Load multi-sig deployment data
  const multiSigDeployment = JSON.parse(
    fs.readFileSync('./deployments/multisig-deployment.json', 'utf8')
  );

  const multiSigAddress = multiSigDeployment.MULTI_SIG_ADDRESS;
  console.log("Multi-sig address:", multiSigAddress);

  // Get deployer signer
  const deployer = await ethers.getSigner(deployerAddress);

  // Multi-sig ABI
  const multiSigAbi = [
    "function ADMIN_ROLE() external view returns (bytes32)",
    "function DEFAULT_ADMIN_ROLE() external view returns (bytes32)",
    "function hasRole(bytes32 role, address account) external view returns (bool)",
    "function grantRole(bytes32 role, address account) external"
  ];

  // Connect to multi-sig contract
  const multiSig = new ethers.Contract(multiSigAddress, multiSigAbi, deployer);

  // Check if deployer has DEFAULT_ADMIN_ROLE
  const DEFAULT_ADMIN_ROLE = await multiSig.DEFAULT_ADMIN_ROLE();
  const hasDefaultAdmin = await multiSig.hasRole(DEFAULT_ADMIN_ROLE, deployerAddress);

  console.log("Has DEFAULT_ADMIN_ROLE:", hasDefaultAdmin);

  if (hasDefaultAdmin) {
    console.log("✅ Deployer already has DEFAULT_ADMIN_ROLE");
    console.log("DEFAULT_ADMIN_ROLE should be able to grant ADMIN_ROLE");
  } else {
    console.log("❌ Deployer does not have DEFAULT_ADMIN_ROLE");
    console.log("Cannot grant ADMIN_ROLE");
    process.exit(1);
  }

  // Grant ADMIN_ROLE to deployer
  const ADMIN_ROLE = await multiSig.ADMIN_ROLE();
  console.log("\nGranting ADMIN_ROLE to deployer...");

  const tx = await multiSig.grantRole(ADMIN_ROLE, deployerAddress);
  console.log("Transaction submitted:", tx.hash);
  await tx.wait();
  console.log("✅ Transaction confirmed");

  // Verify
  const hasAdminRole = await multiSig.hasRole(ADMIN_ROLE, deployerAddress);
  console.log("Has ADMIN_ROLE:", hasAdminRole);

  if (hasAdminRole) {
    console.log("\n✅ Deployer now has ADMIN_ROLE on multi-sig");
    console.log("Can now add hardware wallet owners");
  } else {
    console.log("\n❌ Failed to grant ADMIN_ROLE");
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
