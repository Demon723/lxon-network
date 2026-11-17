const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy LxonUniversalBridge ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const wethAddress = process.env.WETH_MINTABLE || "0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c";
  const validatorRegistry = process.env.BRIDGE_VALIDATOR_REGISTRY;
  const owner = deployer.address;

  console.log("WETH Address:", wethAddress);
  console.log("Validator Registry:", validatorRegistry);
  console.log("Owner:", owner);

  const Bridge = await ethers.getContractFactory("LxonUniversalBridge");
  const bridge = await Bridge.deploy(wethAddress, validatorRegistry, owner);
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();

  console.log("\n✅ LxonUniversalBridge deployed to:", bridgeAddress);

  // Initialize with chain ID 724 (LXON)
  console.log("\n=== Initialize Bridge ===");
  const initTx = await bridge.initialize(724);
  await initTx.wait();
  console.log("✅ Bridge initialized with chain ID 724");

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`UNIVERSAL_BRIDGE=${bridgeAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Configure USDC token for bridging");
  console.log("2. Set peer bridge (Ethereum bridge address)");
  console.log("3. Deploy bridge on Ethereum");
  console.log("4. Test bridging");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
