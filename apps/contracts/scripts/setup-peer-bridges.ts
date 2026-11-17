import { ethers } from "hardhat";

async function main() {
  console.log("🔗 Setting Up Peer Bridges on LxonBridgeMultiSig");

  // Get LxonBridgeMultiSig address
  const bridgeAddress = process.env.LXON_BRIDGE_MULTISIG || "0x692D0047323034514686eF57edFC26DBBa53F87B";
  console.log("LxonBridgeMultiSig:", bridgeAddress);

  // Connect to bridge contract
  const LxonBridgeMultiSig = await ethers.getContractFactory("LxonBridgeMultiSig");
  const bridge = LxonBridgeMultiSig.attach(bridgeAddress);

  // Peer bridge configurations
  // In production, these would be the actual bridge addresses on other chains
  const peerBridges = [
    {
      chainId: 1, // Ethereum Mainnet
      bridgeAddress: "0x0000000000000000000000000000000000000000", // Placeholder - not yet deployed
      name: "Ethereum Mainnet"
    },
    {
      chainId: 11155111, // Sepolia Testnet
      bridgeAddress: "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813", // ✅ Deployed on Sepolia
      name: "Sepolia Testnet"
    },
    {
      chainId: 137, // Polygon Mainnet
      bridgeAddress: "0x2e622d394CFFFA328FFad982c4BcE9d355B16143", // ✅ Deployed on Polygon
      name: "Polygon Mainnet"
    },
    {
      chainId: 17000, // Holesky Testnet
      bridgeAddress: "0x0000000000000000000000000000000000000000", // Placeholder - RPC issues
      name: "Holesky Testnet"
    }
  ];

  console.log("\nSetting up peer bridges...");
  console.log("Note: These are placeholder addresses. Update with actual bridge addresses before production use.\n");

  for (const peer of peerBridges) {
    console.log(`Configuring ${peer.name} (Chain ID: ${peer.chainId})`);
    console.log(`  Bridge Address: ${peer.bridgeAddress}`);

    try {
      const tx = await bridge.setPeerBridge(peer.chainId, peer.bridgeAddress);

      console.log(`  Transaction hash: ${tx.hash}`);
      console.log(`  Waiting for confirmation...`);

      const receipt = await tx.wait();
      console.log(`  ✅ ${peer.name} configured successfully (block ${receipt.blockNumber})`);
    } catch (error: any) {
      console.log(`  ❌ Failed to configure ${peer.name}: ${error.message}`);
    }
  }

  console.log("\n✅ Peer bridge setup complete!");

  // Verify configurations
  console.log("\nVerifying peer bridge configurations...");
  for (const peer of peerBridges) {
    const peerBridge = await bridge.peerBridges(peer.chainId);
    console.log(`\n${peer.name} (Chain ID: ${peer.chainId}):`);
    console.log(`  Peer Bridge: ${peerBridge}`);
  }

  console.log("\n⚠️  IMPORTANT:");
  console.log("  The peer bridge addresses are placeholders (0x0000...)");
  console.log("  Update the script with actual bridge addresses before production use");
  console.log("  Use setPeerBridge() to update peer bridge addresses");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
