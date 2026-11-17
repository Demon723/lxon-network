import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LxonBridgeMinimal to Polygon\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 137n) {
    console.log("\n❌ Wrong network! Please use --network polygon");
    return;
  }

  const WLXON_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const LXON_BRIDGE_ADDRESS = "0x26426Cb29906553A750dB993BC089A80D2922011"; // LXON network bridge

  try {
    console.log("\n=== Deploying LxonBridgeMinimal ===");
    console.log("wLXON Token:", WLXON_ADDRESS);
    console.log("LXON Bridge:", LXON_BRIDGE_ADDRESS);

    const LxonBridge = await ethers.getContractFactory("LxonBridgeMinimal");
    const bridge = await LxonBridge.deploy(137, { gasLimit: 5000000 });

    console.log("Transaction hash:", bridge.deploymentTransaction()?.hash);
    console.log("Waiting for confirmation...");

    await bridge.waitForDeployment();

    const bridgeAddress = await bridge.getAddress();
    console.log("\n✅ LxonBridge Deployed on Polygon!");
    console.log("Bridge Address:", bridgeAddress);
    console.log("Deployer:", deployerAddress);

    console.log("\n=== Post-Deployment Setup ===");
    
    // Set wLXON token
    const setWlxonTx = await bridge.setLxonToken(WLXON_ADDRESS);
    console.log("Setting wLXON token address...");
    await setWlxonTx.wait();
    console.log("✅ wLXON token set");

    // Add wLXON as supported token
    const addTokenTx = await bridge.addToken(WLXON_ADDRESS);
    console.log("Adding wLXON as supported token...");
    await addTokenTx.wait();
    console.log("✅ wLXON token supported");

    // Grant MINTER_ROLE to bridge
    const wlxon = await ethers.getContractAt("LXONWrapper", WLXON_ADDRESS);
    const MINTER_ROLE = await wlxon.MINTER_ROLE();
    const grantRoleTx = await wlxon.grantRole(MINTER_ROLE, bridgeAddress);
    console.log("Granting MINTER_ROLE to bridge...");
    await grantRoleTx.wait();
    console.log("✅ Bridge has MINTER_ROLE");

    console.log("\n=== Important Addresses ===");
    console.log("Polygon Bridge:", bridgeAddress);
    console.log("wLXON Token:", WLXON_ADDRESS);
    console.log("LXON Bridge:", LXON_BRIDGE_ADDRESS);

    console.log("\n=== Next Steps ===");
    console.log("1. Set peer bridge on LXON network:", LXON_BRIDGE_ADDRESS);
    console.log("2. Set peer bridge on Polygon:", bridgeAddress);
    console.log("3. Start bridging LXON ↔ wLXON");

    console.log("\n🎉 Polygon Bridge deployment complete!");

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
