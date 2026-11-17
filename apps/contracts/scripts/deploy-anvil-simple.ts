import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LXON contracts to Anvil...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy LXON token
  console.log("\n1. Deploying LXON token...");
  const LXON = await ethers.deployContract("LXON", [deployer.address]);
  await LXON.waitForDeployment();
  const lxonAddress = await LXON.getAddress();
  console.log("✅ LXON deployed to:", lxonAddress);

  // Deploy Bridge
  console.log("\n2. Deploying LxonBridgeSimpleV2...");
  const Bridge = await ethers.deployContract("LxonBridgeSimpleV2", [724]);
  await Bridge.waitForDeployment();
  const bridgeAddress = await Bridge.getAddress();
  console.log("✅ Bridge deployed to:", bridgeAddress);

  // Grant roles
  console.log("\n3. Granting roles...");
  const ORACLE_ROLE = await LXON.ORACLE_ROLE();
  const MINT_ROLE = await LXON.MINT_ROLE();
  
  await LXON.grantRole(ORACLE_ROLE, deployer.address);
  console.log("✅ Granted ORACLE_ROLE to deployer");

  await LXON.grantRole(MINT_ROLE, deployer.address);
  console.log("✅ Granted MINT_ROLE to deployer");

  // Set reserve ceiling
  console.log("\n4. Setting reserve ceiling...");
  await LXON.setReserveCeiling(ethers.parseUnits("1000000", 6));
  console.log("✅ Reserve ceiling set to 1,000,000 LXON");

  // Mint initial supply
  console.log("\n5. Minting initial supply...");
  await LXON.mint(deployer.address, ethers.parseUnits("1000000", 6), ethers.keccak256(ethers.toUtf8Bytes("test")));
  console.log("✅ Minted 1,000,000 LXON to deployer");

  // Configure bridge
  console.log("\n6. Configuring bridge...");
  await Bridge.configureToken(lxonAddress, 1, true); // MINT_BURN mode
  console.log("✅ Bridge configured for MINT_BURN mode");

  // Verify deployment
  console.log("\n7. Verifying deployment...");
  const balance = await LXON.balanceOf(deployer.address);
  console.log("Deployer balance:", ethers.formatUnits(balance, 6), "LXON");

  console.log("\n🎉 Deployment complete!");
  console.log("LXON:", lxonAddress);
  console.log("Bridge:", bridgeAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
