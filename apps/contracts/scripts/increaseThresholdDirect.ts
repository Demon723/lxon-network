import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("Increasing multi-sig threshold...");

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
    "function getOwners() external view returns (address[])",
    "function threshold() external view returns (uint256)",
    "function ADMIN_ROLE() external view returns (bytes32)",
    "function hasRole(bytes32 role, address account) external view returns (bool)",
    "function changeThreshold(uint256 _threshold) external"
  ];

  // Connect to multi-sig contract
  const multiSig = new ethers.Contract(multiSigAddress, multiSigAbi, deployer);

  // Get current owners and threshold
  const owners = await multiSig.getOwners();
  const currentThreshold = await multiSig.threshold();

  console.log("\nCurrent state:");
  console.log("Total owners:", owners.length);
  console.log("Current threshold:", currentThreshold.toString());

  // Calculate new threshold (2-of-N)
  const newThreshold = 2;
  console.log("\nProposed new threshold:", newThreshold);

  if (newThreshold > owners.length) {
    console.log("❌ Cannot set threshold higher than number of owners");
    process.exit(1);
  }

  if (newThreshold <= currentThreshold) {
    console.log("⚠️  New threshold is not higher than current threshold");
    process.exit(0);
  }

  console.log("\n⚠️  INCREASING THRESHOLD TO", newThreshold);
  console.log("This means", newThreshold, "signatures will be required for all transactions");
  console.log("\nMake sure:");
  console.log("1. All owners have access to their keys");
  console.log("2. Hardware wallets are properly configured");
  console.log("3. Emergency recovery procedures are documented");

  // Wait for confirmation
  console.log("\nPress Ctrl+C to cancel, or wait 10 seconds to proceed...");
  await new Promise(resolve => setTimeout(resolve, 10000));

  // Check if deployer has ADMIN_ROLE
  const ADMIN_ROLE = await multiSig.ADMIN_ROLE();
  const hasAdminRole = await multiSig.hasRole(ADMIN_ROLE, deployerAddress);

  if (!hasAdminRole) {
    console.log("❌ Deployer does not have ADMIN_ROLE on multi-sig");
    process.exit(1);
  }

  console.log("\nIncreasing threshold...");

  const tx = await multiSig.changeThreshold(newThreshold);
  console.log("Transaction submitted:", tx.hash);
  await tx.wait();
  console.log("✅ Transaction confirmed");

  // Verify new threshold
  const newThresholdVerified = await multiSig.threshold();
  console.log("Verified threshold:", newThresholdVerified.toString());

  // Update deployment data
  multiSigDeployment.THRESHOLD = newThresholdVerified.toString();
  multiSigDeployment.THRESHOLD_UPDATE_TIMESTAMP = new Date().toISOString();

  fs.writeFileSync(
    './deployments/multisig-deployment.json',
    JSON.stringify(multiSigDeployment, null, 2)
  );

  console.log("\n=== Threshold Increase Complete ===");
  console.log("New threshold:", newThresholdVerified.toString());
  console.log("Required signatures:", newThresholdVerified.toString(), "of", owners.length);
  console.log("\nSecurity implications:");
  console.log("- All transactions now require", newThresholdVerified.toString(), "signatures");
  console.log("- No single point of failure");
  console.log("- Enhanced security for critical operations");
  console.log("\nNext steps:");
  console.log("1. Test multi-sig operations with new threshold");
  console.log("2. Rotate deployer private key");
  console.log("3. Store deployer key securely or destroy it");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
