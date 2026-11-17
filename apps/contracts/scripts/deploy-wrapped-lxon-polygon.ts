import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying WrappedLxon on Polygon");
  console.log("=====================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "MATIC\n");

  // Deploy WrappedLxon
  console.log("Deploying WrappedLxon...");
  const WrappedLxon = await ethers.getContractFactory("WrappedLXON");
  const wrapped = await WrappedLxon.deploy();

  await wrapped.waitForDeployment();
  const wrappedAddress = await wrapped.getAddress();

  console.log("\n✅ Deployed successfully!");
  console.log("Contract address:", wrappedAddress);
  console.log("Name:", await wrapped.name());
  console.log("Symbol:", await wrapped.symbol());
  console.log("Decimals:", await wrapped.decimals());
  console.log("Admin:", await wrapped.admin());

  // Save deployment info
  const deployment = {
    network: "polygon",
    chainId: 137,
    contractAddress: wrappedAddress,
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };

  const fs = require("fs");
  fs.writeFileSync(
    "./deployments/polygon-wrapped-lxon.json",
    JSON.stringify(deployment, null, 2)
  );

  console.log("\n📝 Deployment saved to: deployments/polygon-wrapped-lxon.json");
  console.log("\n⚠️  IMPORTANT: This is a trust-based contract.");
  console.log("   Only the admin can mint tokens after verifying LXON Chain deposits.");
  console.log("   Users can burn tokens to redeem on LXON Chain.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
