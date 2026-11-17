import { ethers } from "hardhat";

async function main() {
  console.log("🔍 Checking LxonBridgeMultiSig Status");

  const bridgeAddress = process.env.LXON_BRIDGE_MULTISIG || "0x692D0047323034514686eF57edFC26DBBa53F87B";
  const bridge = await ethers.getContractAt("LxonBridgeMultiSig", bridgeAddress);

  const chainId = await bridge.chainId();
  const multiSig = await bridge.multiSigAttester();
  const weth = await bridge.weth();
  const timelock = await bridge.timelock();
  const paused = await bridge.paused();

  console.log("\nBridge Status:");
  console.log("  Chain ID:", chainId.toString());
  console.log("  MultiSigAttester:", multiSig);
  console.log("  WETH:", weth);
  console.log("  Timelock:", timelock);
  console.log("  Paused:", paused);

  console.log("\nToken Configurations:");
  const lxonAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const wethAddress = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
  const usdcAddress = "0x14711906a15BE7Cd861f0378D26b65D37bC5a9df";

  const lxonConfig = await bridge.tokenConfigs(lxonAddress);
  console.log("\nLXON (", lxonAddress, "):");
  console.log("  Mode:", lxonConfig.mode.toString());
  console.log("  Enabled:", lxonConfig.enabled);
  console.log("  Min Amount:", lxonConfig.minAmount.toString());
  console.log("  Max Amount:", lxonConfig.maxAmount.toString());
  console.log("  Daily Limit:", lxonConfig.dailyLimit.toString());

  const wethConfig = await bridge.tokenConfigs(wethAddress);
  console.log("\nWETH (", wethAddress, "):");
  console.log("  Mode:", wethConfig.mode.toString());
  console.log("  Enabled:", wethConfig.enabled);
  console.log("  Min Amount:", wethConfig.minAmount.toString());
  console.log("  Max Amount:", wethConfig.maxAmount.toString());
  console.log("  Daily Limit:", wethConfig.dailyLimit.toString());

  const usdcConfig = await bridge.tokenConfigs(usdcAddress);
  console.log("\nUSDC (", usdcAddress, "):");
  console.log("  Mode:", usdcConfig.mode.toString());
  console.log("  Enabled:", usdcConfig.enabled);
  console.log("  Min Amount:", usdcConfig.minAmount.toString());
  console.log("  Max Amount:", usdcConfig.maxAmount.toString());
  console.log("  Daily Limit:", usdcConfig.dailyLimit.toString());

  console.log("\nPeer Bridges:");
  const ethPeer = await bridge.peerBridges(1);
  const sepoliaPeer = await bridge.peerBridges(11155111);
  const holeskyPeer = await bridge.peerBridges(17000);
  console.log("  Ethereum Mainnet (1):", ethPeer);
  console.log("  Sepolia (11155111):", sepoliaPeer);
  console.log("  Holesky (17000):", holeskyPeer);
}

main().catch(console.error);
