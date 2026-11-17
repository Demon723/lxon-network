const { ethers } = require("ethers");
const fs = require("fs");

// Contract addresses
const BRIDGE_ADDRESS = "0xfDC175150714C7663D626Dd551f829b1Ba748877";
const WETH_ADDRESS = "0x4d857b3e030bA985c5D32611Ff69238975790Be7";
const LXON_ADDRESS = "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35";

// Bridge ABI (simplified)
const BRIDGE_ABI = [
  "function setTokenConfig(address token, uint8 mode, bool enabled, uint256 minAmount, uint256 maxAmount, uint256 dailyLimit) external",
  "function tokenConfigs(address) view returns (uint8 mode, bool enabled, uint256 minAmount, uint256 maxAmount, uint256 dailyLimit, uint256 dailyUsed, uint256 dayStartedAt)",
  "function chainId() view returns (uint256)",
  "function validatorRegistry() view returns (address)",
  "function weth() view returns (address)"
];

async function main() {
  console.log("=== Configuring LXON Bridge ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Configuring with account:", wallet.address);

  const bridge = new ethers.Contract(BRIDGE_ADDRESS, BRIDGE_ABI, wallet);

  // Check current state
  console.log("\n=== Current Bridge State ===");
  const chainId = await bridge.chainId();
  const validatorRegistry = await bridge.validatorRegistry();
  const weth = await bridge.weth();

  console.log("Chain ID:", chainId.toString());
  console.log("Validator Registry:", validatorRegistry);
  console.log("WETH:", weth);

  // Configure WETH (LOCK_UNLOCK mode)
  console.log("\n=== Configuring WETH (LOCK_UNLOCK mode) ===");
  try {
    const tx = await bridge.setTokenConfig(
      WETH_ADDRESS,
      1, // LOCK_UNLOCK mode
      true, // enabled
      ethers.parseEther("0.001"), // minAmount
      ethers.parseEther("100000"), // maxAmount
      ethers.parseEther("1000000") // dailyLimit
    );
    console.log("Transaction submitted:", tx.hash);
    await tx.wait();
    console.log("✅ WETH configured successfully");
  } catch (error) {
    console.error("❌ Failed to configure WETH:", error.message);
  }

  // Configure LXON (MINT_BURN mode) - may fail if LXON doesn't have mint/burn
  console.log("\n=== Configuring LXON (MINT_BURN mode) ===");
  try {
    const tx = await bridge.setTokenConfig(
      LXON_ADDRESS,
      0, // MINT_BURN mode
      true, // enabled
      ethers.parseEther("1"), // minAmount
      ethers.parseEther("10000000"), // maxAmount
      ethers.parseEther("100000000") // dailyLimit
    );
    console.log("Transaction submitted:", tx.hash);
    await tx.wait();
    console.log("✅ LXON configured successfully");
  } catch (error) {
    console.error("❌ Failed to configure LXON (expected if no mint/burn):", error.message);
    console.log("   LXON may not support MINT_BURN mode. Will use LOCK_UNLOCK instead.");

    // Try LOCK_UNLOCK mode instead
    try {
      console.log("\n=== Trying LXON (LOCK_UNLOCK mode) ===");
      const tx = await bridge.setTokenConfig(
        LXON_ADDRESS,
        1, // LOCK_UNLOCK mode
        true, // enabled
        ethers.parseEther("1"), // minAmount
        ethers.parseEther("10000000"), // maxAmount
        ethers.parseEther("100000000") // dailyLimit
      );
      console.log("Transaction submitted:", tx.hash);
      await tx.wait();
      console.log("✅ LXON configured successfully (LOCK_UNLOCK mode)");
    } catch (error2) {
      console.error("❌ Failed to configure LXON in LOCK_UNLOCK mode:", error2.message);
    }
  }

  // Verify configurations
  console.log("\n=== Verifying Configurations ===");

  try {
    const wethConfig = await bridge.tokenConfigs(WETH_ADDRESS);
    console.log("WETH Config:");
    console.log("  Mode:", wethConfig.mode === 0 ? "MINT_BURN" : wethConfig.mode === 1 ? "LOCK_UNLOCK" : "NONE");
    console.log("  Enabled:", wethConfig.enabled);
    console.log("  Min Amount:", ethers.formatEther(wethConfig.minAmount));
    console.log("  Max Amount:", ethers.formatEther(wethConfig.maxAmount));
    console.log("  Daily Limit:", ethers.formatEther(wethConfig.dailyLimit));
  } catch (error) {
    console.error("Failed to read WETH config:", error.message);
  }

  try {
    const lxonConfig = await bridge.tokenConfigs(LXON_ADDRESS);
    console.log("\nLXON Config:");
    console.log("  Mode:", lxonConfig.mode === 0 ? "MINT_BURN" : lxonConfig.mode === 1 ? "LOCK_UNLOCK" : "NONE");
    console.log("  Enabled:", lxonConfig.enabled);
    console.log("  Min Amount:", ethers.formatEther(lxonConfig.minAmount));
    console.log("  Max Amount:", ethers.formatEther(lxonConfig.maxAmount));
    console.log("  Daily Limit:", ethers.formatEther(lxonConfig.dailyLimit));
  } catch (error) {
    console.error("Failed to read LXON config:", error.message);
  }

  console.log("\n=== Bridge Configuration Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
