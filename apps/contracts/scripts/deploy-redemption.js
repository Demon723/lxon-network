const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy LxonRedemption Contract ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const usdcAddress = process.env.USDC_ADDRESS;
  const psmAddress = "0x0000000000000000000000000000000000000000"; // Placeholder - to be updated later
  const custodianWallet = deployer.address; // Initially set to deployer, to be updated later
  const owner = deployer.address;

  console.log("LXON Address:", lxonAddress);
  console.log("USDC Address:", usdcAddress);
  console.log("PSM Address:", psmAddress, "(placeholder)");
  console.log("Custodian Wallet:", custodianWallet);
  console.log("Owner:", owner);

  const Redemption = await ethers.getContractFactory("LxonRedemption");
  const redemption = await Redemption.deploy(
    lxonAddress,
    usdcAddress,
    psmAddress,
    custodianWallet,
    owner
  );
  await redemption.waitForDeployment();
  const redemptionAddress = await redemption.getAddress();

  console.log("\n✅ LxonRedemption deployed to:", redemptionAddress);

  console.log("\n=== Configuration Status ===");
  console.log("✅ LXON token configured");
  console.log("✅ USDC token configured");
  console.log("⚠️ PSM address is placeholder (needs Ethereum PSM deployment)");
  console.log("✅ Custodian wallet set to deployer (update to real custodian later)");

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`LXON_REDEMPTION=${redemptionAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Deploy PSM on Ethereum (need ~0.05 ETH)");
  console.log("2. Update PSM address in redemption contract");
  console.log("3. Sign up with custodian (Fireblocks/BitGo)");
  console.log("4. Update custodian wallet address");
  console.log("5. Deploy backend server for off-ramp");
  console.log("6. Deploy frontend UI");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
