import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔄 Using Existing Test Token as Production LXON on Polygon");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Signer address:", signer.address);

  // Use the test token that's already deployed
  const polygonLxonAddress = "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813";
  const polygonBridgeAddress = "0x2e622d394CFFFA328FFad982c4BcE9d355B16143";
  const lxonBridgeAddress = "0x692D0047323034514686eF57edFC26DBBa53F87B";
  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";

  console.log("\nUsing existing token:", polygonLxonAddress);
  console.log("This token is already configured on the Polygon bridge");

  // Reconfigure token to use production settings
  const polygonBridge = await ethers.getContractAt("LxonBridgeMultiSig", polygonBridgeAddress);
  
  console.log("\nUpdating token configuration for production use...");
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
  console.log("✅ Token configured for production");

  // Update LXON bridge to use Polygon token
  const lxonBridge = await ethers.getContractAt("LxonBridgeMultiSig", lxonBridgeAddress);
  
  console.log("\nUpdating LXON bridge configuration...");
  const lxonConfigTx = await lxonBridge.configureToken(
    lxonTokenAddress,
    2, // LOCK_UNLOCK mode
    true, // enabled
    0, // min amount
    ethers.parseUnits("10000000", 6), // max amount
    ethers.parseUnits("100000000", 6) // daily limit
  );

  console.log("Transaction hash:", lxonConfigTx.hash);
  await lxonConfigTx.wait();
  console.log("✅ LXON bridge configured");

  console.log("\n=== Configuration Complete ===");
  console.log("Polygon LXON Token:", polygonLxonAddress);
  console.log("This token is now configured for production cross-chain transfers");
  console.log("\n⚠️  Note: Using test token as production token for this deployment");
  console.log("For full production, deploy the actual LXON contract when ready");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
