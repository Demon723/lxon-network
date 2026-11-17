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

  // Calculate required ceiling
  // 10T LXON = 10,000,000,000,000 LXON
  // Mint function: amount = usdCents * 1e4
  // So usdCents = 10,000,000,000,000 / 10,000 = 1,000,000,000,000 cents = 10T USD cents = 10B USD
  const requiredCeiling = ethers.parseUnits("1000000000000", 0); // 10T USD cents = 10B USD
  
  console.log("\nSetting reserve ceiling to 10B USD...");
  console.log("Required ceiling:", requiredCeiling.toString(), "cents");

  try {
    const ceilingTx = await lxonToken.updateCeiling(requiredCeiling, ethers.ZeroHash);
    console.log("Transaction hash:", ceilingTx.hash);
    await ceilingTx.wait();
    console.log("✅ Reserve ceiling updated");

    const newCeiling = await lxonToken.reserveCeiling();
    console.log("New reserve ceiling:", newCeiling.toString(), "cents");
  } catch (error: any) {
    console.log("❌ Ceiling update failed:", error.message);
    return;
  }

  // Mint 10T LXON to founder
  const usdCents = ethers.parseUnits("1000000000000", 0); // 10T USD cents
  
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
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
