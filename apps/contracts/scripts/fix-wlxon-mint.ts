import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const wLXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Fixing wLXON mint amount...\n");
  console.log("wLXON Address:", wLXON_ADDRESS);
  console.log("Deployer Address:", deployerAddress);

  const lxon = await ethers.getContractAt("LXONWrapper", wLXON_ADDRESS);
  
  const currentBalance = await lxon.balanceOf(deployerAddress);
  const decimals = await lxon.decimals();

  console.log("\n=== Current State ===");
  console.log("Decimals:", decimals);
  console.log("Current Balance:", ethers.formatUnits(currentBalance, decimals), "wLXON");
  console.log("Raw Balance:", currentBalance.toString());

  // Mint 1,000,000 wLXON with 18 decimals
  // 1,000,000 * 10^18 = 1,000,000,000,000,000,000,000,000
  const mintAmount = ethers.parseUnits("1000000", 18);
  
  console.log("\n=== Minting ===");
  console.log("Mint Amount:", ethers.formatUnits(mintAmount, 18), "wLXON");
  console.log("Raw Amount:", mintAmount.toString());

  try {
    const mintTx = await lxon.mint(deployerAddress, mintAmount);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ Minted successfully!");
    
    const newBalance = await lxon.balanceOf(deployerAddress);
    const newTotalSupply = await lxon.totalSupply();
    
    console.log("\n=== New State ===");
    console.log("New Balance:", ethers.formatUnits(newBalance, 18), "wLXON");
    console.log("New Total Supply:", ethers.formatUnits(newTotalSupply, 18), "wLXON");
    console.log("\n🎉 wLXON balance is now correct!");
  } catch (error: any) {
    console.log("❌ Mint failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
