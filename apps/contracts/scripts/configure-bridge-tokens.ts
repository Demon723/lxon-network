import { ethers } from "hardhat";

async function main() {
  console.log("🔧 Configuring Tokens on LxonBridgeMultiSig");

  // Get LxonBridgeMultiSig address
  const bridgeAddress = process.env.LXON_BRIDGE_MULTISIG || "0x692D0047323034514686eF57edFC26DBBa53F87B";
  console.log("LxonBridgeMultiSig:", bridgeAddress);

  // Connect to bridge contract
  const LxonBridgeMultiSig = await ethers.getContractFactory("LxonBridgeMultiSig");
  const bridge = LxonBridgeMultiSig.attach(bridgeAddress);

  // Token configurations from .env
  // TokenMode enum: NONE=0, MINT_BURN=1, LOCK_UNLOCK=2
  const tokens = [
    {
      address: process.env.LXON_ADDRESS || "0xc0177883C0c662870855660495C697385FE040f5",
      name: "LXON",
      mode: 1, // MINT_BURN
      enabled: true,
      minAmount: 0,
      maxAmount: ethers.parseEther("1000000"), // 1M LXON
      dailyLimit: ethers.parseEther("10000000") // 10M LXON daily
    },
    {
      address: process.env.WETH_ADDRESS || "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4",
      name: "WETH",
      mode: 2, // LOCK_UNLOCK
      enabled: true,
      minAmount: ethers.parseEther("0.01"), // 0.01 WETH
      maxAmount: ethers.parseEther("1000"), // 1000 WETH
      dailyLimit: ethers.parseEther("10000") // 10000 WETH daily
    },
    {
      address: process.env.USDC_ADDRESS || "0x14711906a15BE7Cd861f0378D26b65D37bC5a9df",
      name: "USDC",
      mode: 2, // LOCK_UNLOCK
      enabled: true,
      minAmount: ethers.parseUnits("10", 6), // 10 USDC
      maxAmount: ethers.parseUnits("1000000", 6), // 1M USDC
      dailyLimit: ethers.parseUnits("10000000", 6) // 10M USDC daily
    }
  ];

  console.log("\nConfiguring tokens...");

  for (const token of tokens) {
    console.log(`\nConfiguring ${token.name} (${token.address})`);
    console.log(`  Mode: ${token.mode === 0 ? "MINT_BURN" : "LOCK_UNLOCK"}`);
    console.log(`  Enabled: ${token.enabled}`);
    console.log(`  Min Amount: ${token.minAmount.toString()}`);
    console.log(`  Max Amount: ${token.maxAmount.toString()}`);
    console.log(`  Daily Limit: ${token.dailyLimit.toString()}`);

    try {
      const tx = await bridge.configureToken(
        token.address,
        token.mode,
        token.enabled,
        token.minAmount,
        token.maxAmount,
        token.dailyLimit
      );

      console.log(`  Transaction hash: ${tx.hash}`);
      console.log(`  Waiting for confirmation...`);

      const receipt = await tx.wait();
      console.log(`  ✅ ${token.name} configured successfully (block ${receipt.blockNumber})`);
    } catch (error: any) {
      console.log(`  ❌ Failed to configure ${token.name}: ${error.message}`);
    }
  }

  console.log("\n✅ Token configuration complete!");

  // Verify configurations
  console.log("\nVerifying configurations...");
  for (const token of tokens) {
    const config = await bridge.tokenConfigs(token.address);
    console.log(`\n${token.name}:`);
    console.log(`  Mode: ${config.mode}`);
    console.log(`  Enabled: ${config.enabled}`);
    console.log(`  Min Amount: ${config.minAmount.toString()}`);
    console.log(`  Max Amount: ${config.maxAmount.toString()}`);
    console.log(`  Daily Limit: ${config.dailyLimit.toString()}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
