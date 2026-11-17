import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LxonBridgeMinimal to LXON Network\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 724n) {
    console.log("\n❌ Wrong network! Please use --network lxonMainnet");
    return;
  }

  const DESTINATION_CHAIN_ID = 137; // Polygon
  const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

  try {
    console.log("\n=== Deploying LxonBridgeMinimal ===");
    console.log("LXON Token:", LXON_ADDRESS);
    console.log("Destination Chain ID:", DESTINATION_CHAIN_ID);

    const LxonBridge = await ethers.getContractFactory("LxonBridgeMinimal");
    const bridge = await LxonBridge.deploy(724, { gasLimit: 5000000 });

    console.log("Transaction hash:", bridge.deploymentTransaction()?.hash);
    console.log("Waiting for confirmation...");

    await bridge.waitForDeployment();

    const bridgeAddress = await bridge.getAddress();
    console.log("\n✅ LxonBridge Deployed on LXON Network!");
    console.log("Bridge Address:", bridgeAddress);
    console.log("Deployer:", deployerAddress);

    console.log("\n=== Post-Deployment Setup ===");
    
    // Set LXON token
    const setLxonTx = await bridge.setLxonToken(LXON_ADDRESS);
    console.log("Setting LXON token address...");
    await setLxonTx.wait();
    console.log("✅ LXON token set");

    // Add LXON as supported token
    const addTokenTx = await bridge.addToken(LXON_ADDRESS);
    console.log("Adding LXON as supported token...");
    await addTokenTx.wait();
    console.log("✅ LXON token supported");

    // Set admin (deployer is already admin by default)
    console.log("Admin:", deployerAddress);

    // Set peer bridge on Polygon (will be set after Polygon deployment)
    console.log("\n=== Next Steps ===");
    console.log("1. Deploy LxonBridgeMinimal on Polygon");
    console.log("2. Set peer bridge addresses on both sides");
    console.log("3. Start bridging LXON ↔ wLXON");

    console.log("\n=== Important Addresses ===");
    console.log("LXON Bridge:", bridgeAddress);
    console.log("LXON Token:", LXON_ADDRESS);
    console.log("Destination Chain:", "Polygon (137)");

    console.log("\n🎉 LXON Bridge deployment complete!");

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
