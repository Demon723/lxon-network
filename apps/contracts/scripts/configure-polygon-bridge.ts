import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("⚙️  Configuring LXON Token on Polygon Bridge");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Signer address:", signer.address);

  // Contract addresses
  const polygonBridgeAddress = "0x2e622d394CFFFA328FFad982c4BcE9d355B16143";
  const polygonLxonAddress = "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813";
  const lxonChainId = 724;

  // Connect to Polygon bridge
  const polygonBridge = await ethers.getContractAt("LxonBridgeMultiSig", polygonBridgeAddress);

  console.log("\nPolygon Bridge:", polygonBridgeAddress);
  console.log("LXON Token:", polygonLxonAddress);
  console.log("LXON Chain ID:", lxonChainId);

  // Configure token on Polygon bridge
  console.log("\nConfiguring LXON token on Polygon bridge...");
  console.log("  Mode: LOCK_UNLOCK (since token exists on both chains)");
  console.log("  Min: 0");
  console.log("  Max: 1,000,000");
  console.log("  Daily Limit: 10,000,000");

  try {
    const configTx = await polygonBridge.configureToken(
      polygonLxonAddress,
      2, // LOCK_UNLOCK mode
      true, // enabled
      0, // min amount
      ethers.parseUnits("1000000", 6), // max amount
      ethers.parseUnits("10000000", 6) // daily limit
    );

    console.log("Transaction hash:", configTx.hash);
    console.log("Waiting for confirmation...");
    await configTx.wait();
    console.log("✅ Token configured on Polygon bridge");

    // Verify configuration
    const config = await polygonBridge.tokenConfigs(polygonLxonAddress);
    console.log("\nToken configuration:");
    console.log("  Mode:", config.mode.toString());
    console.log("  Enabled:", config.enabled);
    console.log("  Min:", config.minAmount.toString());
    console.log("  Max:", config.maxAmount.toString());
    console.log("  Daily Limit:", config.dailyLimit.toString());

  } catch (error: any) {
    console.log("❌ Configuration failed:", error.message);
  }

  // Configure peer bridge on Polygon
  console.log("\nConfiguring LXON peer bridge on Polygon...");
  const lxonBridgeAddress = "0x692D0047323034514686eF57edFC26DBBa53F87B";

  try {
    const peerTx = await polygonBridge.setPeerBridge(lxonChainId, lxonBridgeAddress);
    console.log("Transaction hash:", peerTx.hash);
    console.log("Waiting for confirmation...");
    await peerTx.wait();
    console.log("✅ Peer bridge configured on Polygon");

    // Verify configuration
    const peerBridge = await polygonBridge.peerBridges(lxonChainId);
    console.log("\nPeer bridge configuration:");
    console.log("  Chain ID:", lxonChainId);
    console.log("  Bridge:", peerBridge);

  } catch (error: any) {
    console.log("❌ Peer bridge configuration failed:", error.message);
  }

  console.log("\n=== Configuration Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
