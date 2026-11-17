import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("Adding hardware wallet to multi-sig (direct method)...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const hardwareWalletAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Deployer address:", deployerAddress);
  console.log("Hardware wallet address:", hardwareWalletAddress);

  // Load multi-sig deployment data
  const multiSigDeployment = JSON.parse(
    fs.readFileSync('./deployments/multisig-deployment.json', 'utf8')
  );

  const multiSigAddress = multiSigDeployment.MULTI_SIG_ADDRESS;
  console.log("Multi-sig address:", multiSigAddress);

  // Get deployer signer
  const deployer = await ethers.getSigner(deployerAddress);

  // Multi-sig ABI (only the functions we need)
  const multiSigAbi = [
    "function addOwner(address owner) external",
    "function isOwnerCheck(address account) external view returns (bool)",
    "function getOwners() external view returns (address[])",
    "function ADMIN_ROLE() external view returns (bytes32)",
    "function hasRole(bytes32 role, address account) external view returns (bool)"
  ];

  // Connect to multi-sig contract
  const multiSig = new ethers.Contract(multiSigAddress, multiSigAbi, deployer);

  // Check if already an owner
  const isAlreadyOwner = await multiSig.isOwnerCheck(hardwareWalletAddress);
  if (isAlreadyOwner) {
    console.log("⚠️  Hardware wallet is already an owner");
    process.exit(0);
  }

  console.log("\nAdding hardware wallet as owner...");

  // Check if deployer has ADMIN_ROLE
  const ADMIN_ROLE = await multiSig.ADMIN_ROLE();
  const hasAdminRole = await multiSig.hasRole(ADMIN_ROLE, deployerAddress);

  if (!hasAdminRole) {
    console.log("❌ Deployer does not have ADMIN_ROLE on multi-sig");
    console.log("Please grant ADMIN_ROLE to deployer first");
    process.exit(1);
  }

  // Add hardware wallet as owner
  const tx = await multiSig.addOwner(hardwareWalletAddress);
  console.log("Transaction submitted:", tx.hash);
  await tx.wait();
  console.log("✅ Transaction confirmed");

  // Get updated owners list
  const owners = await multiSig.getOwners();
  console.log("\nCurrent owners:");
  owners.forEach((owner: string, index: number) => {
    console.log(`${index + 1}. ${owner}`);
  });

  // Update deployment data
  multiSigDeployment.OWNERS = owners;
  multiSigDeployment.HARDWARE_WALLET_ADDED = true;
  multiSigDeployment.HARDWARE_WALLET_ADDRESS = hardwareWalletAddress;
  multiSigDeployment.UPDATE_TIMESTAMP = new Date().toISOString();

  fs.writeFileSync(
    './deployments/multisig-deployment.json',
    JSON.stringify(multiSigDeployment, null, 2)
  );

  console.log("\n=== Hardware Wallet Addition Complete ===");
  console.log("Hardware wallet:", hardwareWalletAddress);
  console.log("Total owners:", owners.length);
  console.log("\nNext steps:");
  console.log("1. Test hardware wallet can sign transactions");
  console.log("2. Increase threshold to 2-of-" + owners.length);
  console.log("3. Rotate deployer private key");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
