import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LxonBridge on Polygon");
  console.log("===================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "MATIC\n");

  // Deploy bridge
  console.log("Deploying LxonBridge...");
  const Bridge = await ethers.getContractFactory("LxonBridge");
  const bridge = await Bridge.deploy(137); // Polygon chain ID

  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();

  console.log("\n✅ Deployed successfully!");
  console.log("Contract address:", bridgeAddress);
  console.log("Chain ID:", 137);
  console.log("Owner:", await bridge.owner());
  console.log("Min confirmations:", await bridge.minConfirmations());
  console.log("Max transfer amount:", ethers.formatEther(await bridge.maxTransferAmount()));

  // Add deployer as validator
  console.log("\nAdding deployer as validator...");
  await bridge.addValidator(deployer.address);
  console.log("✅ Validator added");

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
    "./deployments/polygon-lxon-bridge.json",
    JSON.stringify(deployment, null, 2)
  );

  console.log("\n📝 Deployment saved to: deployments/polygon-lxon-bridge.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
