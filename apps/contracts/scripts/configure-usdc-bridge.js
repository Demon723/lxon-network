const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Configure Bridge for USDC ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const bridgeAddress = process.env.UNIVERSAL_BRIDGE;
  const usdcAddress = process.env.USDC_ADDRESS;

  console.log("Bridge Address:", bridgeAddress);
  console.log("USDC Address:", usdcAddress);

  const Bridge = await ethers.getContractFactory("LxonUniversalBridge");
  const bridge = Bridge.attach(bridgeAddress);

  // Configure USDC as ERC20 with LOCK_UNLOCK mode
  // LOCK_UNLOCK = 1, ERC20 = 1
  console.log("\n=== Configure USDC Token ===");
  const configTx = await bridge.setTokenConfig(
    usdcAddress,
    1, // TokenMode.LOCK_UNLOCK
    1, // TokenType.ERC20
    true, // enabled
    ethers.parseUnits("1", 18), // minAmount: 1 USDC
    ethers.parseUnits("1000000", 18), // maxAmount: 1M USDC
    ethers.parseUnits("10000000", 18) // dailyLimit: 10M USDC
  );
  console.log("Transaction:", configTx.hash);
  await configTx.wait();
  console.log("✅ USDC configured for bridging");

  // Verify configuration
  const config = await bridge.tokenConfigs(usdcAddress);
  console.log("\n=== Token Configuration ===");
  console.log("Mode:", config.mode.toString());
  console.log("Type:", config.tokenType.toString());
  console.log("Enabled:", config.enabled);
  console.log("Min Amount:", ethers.formatUnits(config.minAmount, 18));
  console.log("Max Amount:", ethers.formatUnits(config.maxAmount, 18));
  console.log("Daily Limit:", ethers.formatUnits(config.dailyLimit, 18));

  console.log("\n=== Summary ===");
  console.log("✅ USDC is now configured for bridging on LXON network");
  console.log("✅ Users can bridge USDC from LXON to Ethereum (once Ethereum bridge is deployed)");
  console.log("✅ Mode: LOCK_UNLOCK (tokens are locked in escrow)");
  console.log("\n=== Next Steps ===");
  console.log("1. Deploy same bridge on Ethereum Mainnet");
  console.log("2. Set peer bridge addresses (LXON ↔ Ethereum)");
  console.log("3. Start validators/relayers");
  console.log("4. Test bridging");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
