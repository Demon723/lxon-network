import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("⚙️  Configuring REAL LXON Token on Polygon Bridge");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const provider = new ethers.JsonRpcProvider("https://polygon.drpc.org");
  const signer = new ethers.Wallet(privateKey, provider);
  
  console.log("Signer address:", signer.address);

  // Contract addresses
  const polygonBridgeAddress = "0x2e622d394CFFFA328FFad982c4BcE9d355B16143";
  const polygonLxonAddress = "0xf6B053bE2849B057FC182aC6De62867662d2A206"; // NEW REAL TOKEN
  const lxonChainId = 724;
  const lxonBridgeAddress = "0x692D0047323034514686eF57edFC26DBBa53F87B";
  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";

  console.log("\nPolygon Bridge:", polygonBridgeAddress);
  console.log("NEW Real LXON Token:", polygonLxonAddress);
  console.log("LXON Chain ID:", lxonChainId);

  // Connect to Polygon bridge
  const polygonBridge = await ethers.getContractAt("LxonBridgeMultiSig", polygonBridgeAddress, signer);

  // Configure new token on Polygon bridge
  console.log("\nConfiguring REAL LXON token on Polygon bridge...");
  const configTx = await polygonBridge.configureToken(
    polygonLxonAddress,
    2, // LOCK_UNLOCK mode
    true, // enabled
    0, // min amount
    ethers.parseUnits("10000000", 6), // max amount (10M)
    ethers.parseUnits("100000000", 6) // daily limit (100M)
  );

  console.log("Transaction hash:", configTx.hash);
  await configTx.wait();
  console.log("✅ Real LXON token configured on Polygon bridge");

  // Verify configuration
  const config = await polygonBridge.tokenConfigs(polygonLxonAddress);
  console.log("\nToken configuration:");
  console.log("  Mode:", config.mode.toString());
  console.log("  Enabled:", config.enabled);
  console.log("  Max:", ethers.formatUnits(config.maxAmount, 6), "LXON");
  console.log("  Daily Limit:", ethers.formatUnits(config.dailyLimit, 6), "LXON");

  // Update .env with new address
  console.log("\n=== Configuration Complete ===");
  console.log("Add to .env:");
  console.log(`POLYGON_LXON_ADDRESS=${polygonLxonAddress}`);
  console.log(`POLYGON_RPC_URL=https://polygon.drpc.org`);
  console.log("\n✅ Real LXON token is now configured on Polygon bridge");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
