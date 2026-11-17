import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("⚙️  Configuring LXON Token on Sepolia Bridge");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Signer address:", signer.address);

  // Contract addresses
  const sepoliaBridgeAddress = "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813";
  const sepoliaLxonAddress = "0x286E4AB4a5B422844F3cdb6A0c6D191C6EB36847";
  const lxonChainId = 724;

  // Connect to Sepolia bridge
  const sepoliaBridge = await ethers.getContractAt("LxonBridgeMultiSig", sepoliaBridgeAddress);

  console.log("\nSepolia Bridge:", sepoliaBridgeAddress);
  console.log("LXON Token:", sepoliaLxonAddress);
  console.log("LXON Chain ID:", lxonChainId);

  // Configure token on Sepolia bridge
  console.log("\nConfiguring LXON token on Sepolia bridge...");
  console.log("  Mode: LOCK_UNLOCK (since token exists on both chains)");
  console.log("  Min: 0");
  console.log("  Max: 1,000,000");
  console.log("  Daily Limit: 10,000,000");

  try {
    const configTx = await sepoliaBridge.configureToken(
      sepoliaLxonAddress,
      2, // LOCK_UNLOCK mode
      true, // enabled
      0, // min amount
      ethers.parseUnits("1000000", 6), // max amount
      ethers.parseUnits("10000000", 6) // daily limit
    );

    console.log("Transaction hash:", configTx.hash);
    console.log("Waiting for confirmation...");
    await configTx.wait();
    console.log("✅ Token configured on Sepolia bridge");

    // Verify configuration
    const config = await sepoliaBridge.tokenConfigs(sepoliaLxonAddress);
    console.log("\nToken configuration:");
    console.log("  Mode:", config.mode.toString());
    console.log("  Enabled:", config.enabled);
    console.log("  Min:", config.minAmount.toString());
    console.log("  Max:", config.maxAmount.toString());
    console.log("  Daily Limit:", config.dailyLimit.toString());

  } catch (error: any) {
    console.log("❌ Configuration failed:", error.message);
    console.log("\nNote: Token configuration requires timelock admin rights.");
    console.log("The bridge may need to be called from the timelock address.");
  }

  // Configure peer bridge on Sepolia
  console.log("\nConfiguring LXON peer bridge on Sepolia...");
  const lxonBridgeAddress = "0x692D0047323034514686eF57edFC26DBBa53F87B";

  try {
    const peerTx = await sepoliaBridge.setPeerBridge(lxonChainId, lxonBridgeAddress);
    console.log("Transaction hash:", peerTx.hash);
    console.log("Waiting for confirmation...");
    await peerTx.wait();
    console.log("✅ Peer bridge configured on Sepolia");

    // Verify configuration
    const peerBridge = await sepoliaBridge.peerBridges(lxonChainId);
    console.log("\nPeer bridge configuration:");
    console.log("  Chain ID:", lxonChainId);
    console.log("  Bridge:", peerBridge);

  } catch (error: any) {
    console.log("❌ Peer bridge configuration failed:", error.message);
    console.log("\nNote: Peer bridge configuration requires timelock admin rights.");
  }

  console.log("\n=== Configuration Complete ===");
  console.log("Note: If transactions failed, they need to be executed via timelock governance.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
