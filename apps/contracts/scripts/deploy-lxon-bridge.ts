import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying LXON Bridge to LXON Network\n");
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

  const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
  const DESTINATION_CHAIN_ID = 137; // Polygon

  try {
    console.log("\n=== Deploying LXON Bridge ===");
    console.log("LXON Token:", LXON_ADDRESS);
    console.log("Destination Chain ID:", DESTINATION_CHAIN_ID);

    const LXONBridge = await ethers.getContractFactory("LXONBridgeNew");
    const bridge = await LXONBridge.deploy(LXON_ADDRESS, DESTINATION_CHAIN_ID);

    console.log("Transaction hash:", bridge.deploymentTransaction()?.hash);
    console.log("Waiting for confirmation...");

    await bridge.waitForDeployment();

    const bridgeAddress = await bridge.getAddress();
    console.log("\n✅ LXON Bridge Deployed!");
    console.log("Bridge Address:", bridgeAddress);
    console.log("Deployer:", deployerAddress);

    console.log("\n=== Post-Deployment Setup ===");
    
    // Approve bridge to spend LXON
    const lxon = await ethers.getContractAt("IERC20", LXON_ADDRESS);
    const approveAmount = ethers.parseUnits("100000000", 6); // 100M LXON
    const approveTx = await lxon.approve(bridgeAddress, approveAmount);
    console.log("Approving bridge to spend LXON...");
    await approveTx.wait();
    console.log("✅ Bridge approved to spend LXON");

    console.log("\n=== Important Addresses ===");
    console.log("LXON Bridge:", bridgeAddress);
    console.log("LXON Token:", LXON_ADDRESS);
    console.log("Destination Chain:", "Polygon (137)");

    console.log("\n🎉 Bridge deployment complete!");
    console.log("Next: Deploy wLXON Bridge on Polygon");

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
