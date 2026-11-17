const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  console.log("=== Check LXON Bridge Deployment Status ===\n");

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");
  
  const bridgeAddress = process.env.LXON_BRIDGE;
  console.log("LXON Bridge Address from .env:", bridgeAddress);

  if (bridgeAddress) {
    console.log("\n=== Checking if bridge is deployed ===");
    const code = await provider.getCode(bridgeAddress);
    if (code !== "0x") {
      console.log("✅ Bridge is deployed at:", bridgeAddress);
      console.log("Contract size:", code.length, "bytes");
    } else {
      console.log("❌ Bridge address is set but contract not deployed");
    }
  } else {
    console.log("❌ No bridge address in .env");
  }

  console.log("\n=== What's Needed for Real USDC Bridging ===");
  console.log("1. Deploy LXONBridge on LXON network");
  console.log("2. Deploy LXONBridge on Ethereum network");
  console.log("3. Configure validators on both sides");
  console.log("4. Set up peer bridges (LXON ↔ Ethereum)");
  console.log("5. Configure USDC in LOCK_UNLOCK mode");
  console.log("6. Integrate real USDC (Ethereum) to bridge");
  console.log("\n=== LayerZero/Wormhole Integration ===");
  console.log("❌ Cannot integrate with LayerZero - requires official partnership");
  console.log("❌ Cannot integrate with Wormhole - requires official partnership");
  console.log("   These are proprietary bridge networks");
  console.log("   They require chain to apply and be approved");
  console.log("   LXON team must contact them for integration");
  console.log("\n=== Conclusion ===");
  console.log("To get real USDC on LXON:");
  console.log("1. Contact LXON team to deploy LXONBridge");
  console.log("2. Contact LayerZero/Wormhole for integration");
  console.log("3. Or use custom USDC for internal trading");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
