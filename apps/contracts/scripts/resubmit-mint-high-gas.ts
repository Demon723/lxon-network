import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const wLXON_ADDRESS = process.env.POLYGON_LXON_ADDRESS || "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Resubmitting mint transaction with higher gas...\n");
  console.log("wLXON Address:", wLXON_ADDRESS);
  console.log("Deployer Address:", deployerAddress);

  const lxon = await ethers.getContractAt("LXONWrapper", wLXON_ADDRESS);
  
  // Mint 1,000,000 wLXON with 18 decimals
  const mintAmount = ethers.parseUnits("1000000", 18);
  
  console.log("\n=== Minting with Higher Gas ===");
  console.log("Mint Amount:", ethers.formatUnits(mintAmount, 18), "wLXON");
  console.log("Gas Price: 100 gwei (was 312 gwei, but network is now ~285 gwei)");
  console.log("This should confirm in 1-2 minutes");

  try {
    const mintTx = await lxon.mint(deployerAddress, mintAmount, {
      gasPrice: ethers.parseUnits("100", "gwei"),
      gasLimit: 100000
    });
    console.log("\nMint transaction:", mintTx.hash);
    console.log("Waiting for confirmation...");
    
    const receipt = await mintTx.wait();
    
    console.log("\n✅ Minted successfully!");
    console.log("Transaction hash:", receipt?.hash);
    console.log("Gas used:", receipt?.gasUsed.toString());
    console.log("Gas price:", ethers.formatUnits(receipt?.gasPrice || 0, "gwei"), "gwei");
    
    const newBalance = await lxon.balanceOf(deployerAddress);
    const newTotalSupply = await lxon.totalSupply();
    
    console.log("\n=== New State ===");
    console.log("New Balance:", ethers.formatUnits(newBalance, 18), "wLXON");
    console.log("New Total Supply:", ethers.formatUnits(newTotalSupply, 18), "wLXON");
    console.log("\n🎉 You now have 1,000,000 wLXON!");
    console.log("You can proceed to add liquidity via SushiSwap UI");
    
  } catch (error: any) {
    console.log("\n❌ Mint failed:", error.message);
    if (error.message.includes("nonce")) {
      console.log("\n💡 The previous transaction might have confirmed.");
      console.log("   Check your balance on Polygonscan:");
      console.log("   https://polygonscan.com/token/0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
