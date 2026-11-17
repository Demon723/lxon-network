import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("💰 Minting 10T Real LXON to Founder Address");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  const founderAddress = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";

  console.log("Deployer:", signer.address);
  console.log("Founder:", founderAddress);

  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const lxonToken = await ethers.getContractAt("LXON", lxonTokenAddress);

  // Check current reserve ceiling
  const currentCeiling = await lxonToken.reserveCeiling();
  console.log("\nCurrent reserve ceiling:", currentCeiling.toString(), "cents");

  // Set reserve ceiling to accommodate 10T LXON
  // 10T LXON = 10,000,000,000,000 LXON
  // Since minting is in USD cents: 10T LXON / 10,000 = 1B USD cents = 100,000,000,000 cents
  const newCeiling = ethers.parseUnits("100000000000", 0); // 100B cents = 1T USD ceiling
  console.log("Setting reserve ceiling to 1T USD...");

  try {
    const ceilingTx = await lxonToken.updateCeiling(newCeiling, ethers.ZeroHash);
    console.log("Transaction hash:", ceilingTx.hash);
    await ceilingTx.wait();
    console.log("✅ Reserve ceiling updated");
  } catch (error: any) {
    console.log("❌ Ceiling update failed:", error.message);
    console.log("Proceeding with current ceiling...");
  }

  // Mint 10T LXON to founder
  // Mint function takes usdCents, and multiplies by 1e4 internally
  // 10T LXON = 10,000,000,000,000 LXON
  // usdCents needed = 10,000,000,000,000 / 10,000 = 1,000,000,000 cents = 10B USD
  const usdCents = ethers.parseUnits("10000000000", 0); // 10B USD cents
  
  console.log("\nMinting 10T LXON to founder...");
  console.log("USD Cents:", usdCents.toString());

  try {
    const mintTx = await lxonToken.mint(founderAddress, usdCents, ethers.ZeroHash);
    console.log("Transaction hash:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ Minting successful");

    // Verify balance
    const founderBalance = await lxonToken.balanceOf(founderAddress);
    console.log("\nFounder balance:", ethers.formatUnits(founderBalance, 6), "LXON");

    // Check total supply
    const totalSupply = await lxonToken.totalSupply();
    console.log("Total supply:", ethers.formatUnits(totalSupply, 6), "LXON");

    console.log("\n=== Minting Complete ===");
    console.log("✅ 10T LXON minted to founder address");

  } catch (error: any) {
    console.log("❌ Minting failed:", error.message);
    console.log("\nPossible reasons:");
    console.log("  - Reserve ceiling too low");
    console.log("  - Insufficient permissions");
    console.log("  - Contract paused");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
