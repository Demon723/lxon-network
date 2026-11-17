import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const wLXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Checking wLXON balance...\n");
  console.log("wLXON Address:", wLXON_ADDRESS);
  console.log("Deployer Address:", deployerAddress);

  const lxon = await ethers.getContractAt("LXONWrapper", wLXON_ADDRESS);
  
  const balance = await lxon.balanceOf(deployerAddress);
  const totalSupply = await lxon.totalSupply();
  const symbol = await lxon.symbol();
  const name = await lxon.name();
  const decimals = await lxon.decimals();

  console.log("\n=== Token Info ===");
  console.log("Name:", name);
  console.log("Symbol:", symbol);
  console.log("Decimals:", decimals);
  console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals), symbol);
  
  console.log("\n=== Deployer Balance ===");
  console.log("Balance:", ethers.formatUnits(balance, decimals), symbol);
  console.log("Raw Balance:", balance.toString());

  if (balance === 0n) {
    console.log("\n❌ Balance is 0 - minting may have failed");
    console.log("Attempting to mint 1,000,000 wLXON...");
    
    try {
      const mintAmount = ethers.parseUnits("1000000", 6);
      const mintTx = await lxon.mint(deployerAddress, mintAmount);
      console.log("Mint transaction:", mintTx.hash);
      await mintTx.wait();
      console.log("✅ Minted successfully!");
      
      const newBalance = await lxon.balanceOf(deployerAddress);
      console.log("New Balance:", ethers.formatUnits(newBalance, 6), symbol);
    } catch (error: any) {
      console.log("❌ Mint failed:", error.message);
    }
  } else {
    console.log("\n✅ Balance is correct!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
