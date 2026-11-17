import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LxonBridgeMinimal on Polygon");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "MATIC\n");

  // Deploy minimal bridge
  console.log("Deploying LxonBridgeMinimal...");
  const Bridge = await ethers.getContractFactory("LxonBridgeMinimal");
  const bridge = await Bridge.deploy(137); // Polygon chain ID

  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();

  console.log("\n✅ Deployed successfully!");
  console.log("Contract address:", bridgeAddress);
  console.log("Chain ID:", await bridge.chainId());
  console.log("Admin:", await bridge.admin());

  // Save deployment info
  const deployment = {
    network: "polygon",
    chainId: 137,
    bridgeAddress: bridgeAddress,
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };

  const fs = require("fs");
  fs.writeFileSync(
    "./deployments/polygon-minimal-bridge.json",
    JSON.stringify(deployment, null, 2)
  );

  console.log("\n📝 Deployment saved to: deployments/polygon-minimal-bridge.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
