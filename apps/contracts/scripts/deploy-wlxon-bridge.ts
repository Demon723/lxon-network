import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying wLXON Bridge to Polygon\n");
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
  const SOURCE_CHAIN_ID = 724; // LXON Network

  try {
    console.log("\n=== Deploying wLXON Bridge ===");
    console.log("wLXON Token:", WLXON_ADDRESS);
    console.log("Source Chain ID:", SOURCE_CHAIN_ID);

    const wLXONBridge = await ethers.getContractFactory("wLXONBridge");
    const bridge = await wLXONBridge.deploy(WLXON_ADDRESS, SOURCE_CHAIN_ID);

    console.log("Transaction hash:", bridge.deploymentTransaction()?.hash);
    console.log("Waiting for confirmation...");

    await bridge.waitForDeployment();

    const bridgeAddress = await bridge.getAddress();
    console.log("\n✅ wLXON Bridge Deployed!");
    console.log("Bridge Address:", bridgeAddress);
    console.log("Deployer:", deployerAddress);

    console.log("\n=== Post-Deployment Setup ===");
    
    // Grant mint role to bridge
    const wlxon = await ethers.getContractAt("LXONWrapper", WLXON_ADDRESS);
    const MINTER_ROLE = await wlxon.MINTER_ROLE();
    const grantRoleTx = await wlxon.grantRole(MINTER_ROLE, bridgeAddress);
    console.log("Granting MINTER_ROLE to bridge...");
    await grantRoleTx.wait();
    console.log("✅ Bridge has MINTER_ROLE");

    console.log("\n=== Important Addresses ===");
    console.log("wLXON Bridge:", bridgeAddress);
    console.log("wLXON Token:", WLXON_ADDRESS);
    console.log("Source Chain:", "LXON Network (724)");

    console.log("\n🎉 Bridge deployment complete!");
    console.log("Next: Deploy the relayer to monitor cross-chain messages");

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
