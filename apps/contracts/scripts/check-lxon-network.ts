import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔍 Checking LXON Network Status\n");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer:", deployerAddress);

  try {
    // Check network
    const network = await ethers.provider.getNetwork();
    console.log("\n=== Network ===");
    console.log("Chain ID:", network.chainId);
    console.log("Network name:", network.name);

    const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";

    // Connect to LXON contract
    const lxon = await ethers.getContractAt("LXON", LXON_ADDRESS);
    
    // Check balance
    const balance = await lxon.balanceOf(deployerAddress);
    const decimals = await lxon.decimals();

    console.log("\n=== LXON Token Info ===");
    console.log("Contract Address:", LXON_ADDRESS);
    console.log("Decimals:", decimals.toString());
    console.log("Your Balance:", ethers.formatUnits(balance, decimals));
    console.log("Raw Balance:", balance.toString());

    // Check if deployer has MINT_ROLE
    const MINT_ROLE = await lxon.MINT_ROLE();
    const hasMintRole = await lxon.hasRole(MINT_ROLE, deployerAddress);
    console.log("\n=== Roles ===");
    console.log("Has MINT_ROLE:", hasMintRole);

    if (hasMintRole) {
      console.log("\n✅ You can mint more LXON on LXON network");
    } else {
      console.log("\n❌ You do not have MINT_ROLE - cannot mint more LXON");
    }

  } catch (error: any) {
    console.log("\n❌ Error:", error.message);
    console.log("LXON network RPC might be down or unreachable");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
