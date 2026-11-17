import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Gnosis Safe multi-sig for LXON...");

  const deployerAddress = "0xb6751d9FfAfcAe559a0EA45e5ad9965dEC87AFe5";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deployer address:", deployerAddress);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Since Gnosis Safe contracts are complex, we'll use a simpler multi-sig approach
  // deploying a custom multi-sig contract for LXON

  console.log("\nDeploying simplified multi-sig contract...");

  const MultiSig = await ethers.getContractFactory("MultiSigWallet");
  const multiSig = await MultiSig.deploy(
    [
      deployerAddress, // Owner 1 (current deployer)
      // Add additional owners as needed
    ],
    1 // Threshold: 1 signature required initially (will increase after adding more owners)
  );
  await multiSig.waitForDeployment();

  const multiSigAddress = await multiSig.getAddress();
  console.log("Multi-sig deployed to:", multiSigAddress);

  // Save deployment data
  const fs = require('fs');
  const deploymentData = {
    MULTI_SIG_ADDRESS: multiSigAddress,
    OWNERS: [deployerAddress],
    THRESHOLD: 1,
    DEPLOYER: deployerAddress,
    DEPLOYMENT_TIMESTAMP: new Date().toISOString()
  };

  fs.writeFileSync(
    './deployments/multisig-deployment.json',
    JSON.stringify(deploymentData, null, 2)
  );

  console.log("\n=== Multi-Sig Deployment Complete ===");
  console.log("Multi-Sig Address:", multiSigAddress);
  console.log("Owners:", deploymentData.OWNERS);
  console.log("Threshold:", deploymentData.THRESHOLD);
  console.log("\nNext steps:");
  console.log("1. Add additional owners (hardware wallets)");
  console.log("2. Transfer contract ownership to multi-sig");
  console.log("3. Test multi-sig operations");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
