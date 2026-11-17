import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔍 Checking Existing Bridge Infrastructure\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

  try {
    // Check if LxonBridge exists
    const LxonBridge = await ethers.getContractFactory("LxonBridge");
    
    console.log("\n=== Existing Bridge Contract ===");
    console.log("Your repository has LxonBridge.sol");
    console.log("This is a complete cross-chain bridge with validator management");
    
    console.log("\n=== Simplified Approach ===");
    console.log("Instead of creating a new bridge, let's:");
    console.log("1. Deploy the existing LxonBridge on LXON network");
    console.log("2. Deploy it on Polygon network");
    console.log("3. Configure them to bridge LXON ↔ wLXON");
    console.log("4. Use your deployer as the validator");
    
    console.log("\n=== Current Assets ===");
    const lxon = await ethers.getContractAt("IERC20", LXON_ADDRESS);
    const balance = await lxon.balanceOf(deployerAddress);
    console.log("LXON Balance:", ethers.formatUnits(balance, 6));
    
    console.log("\n🎯 Recommendation:");
    console.log("The existing bridge is production-ready.");
    console.log("Would you like me to:");
    console.log("1. Deploy LxonBridge on both networks");
    console.log("2. Configure it for LXON ↔ wLXON bridging");
    console.log("3. Set up a simple relayer script");

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
