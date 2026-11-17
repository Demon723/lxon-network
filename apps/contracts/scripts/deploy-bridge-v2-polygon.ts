import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LxonBridgeSimpleV2 on Polygon");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "POL\n");

  // Polygon chain ID
  const chainId = 137;
  
  console.log("Deploying LxonBridgeSimpleV2...");
  const Bridge = await ethers.getContractFactory("LxonBridgeSimpleV2");
  const bridge = await Bridge.deploy(chainId, {
    gasLimit: 2000000,
    gasPrice: ethers.parseUnits("30", "gwei"),
  });
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  console.log("✅ Bridge deployed:", bridgeAddress);

  // Set admin (deployer)
  console.log("\nSetting admin...");
  await (await bridge.setAdmin(deployer.address)).wait();
  console.log("✅ Admin set:", deployer.address);

  // Configure token (LXON on Polygon)
  console.log("\nConfiguring LXON token...");
  const lxonToken = "0xf6B053bE2849B057FC182aC6De62867662d2A206";
  await (await bridge.configureToken(
    lxonToken,
    2, // MINT_BURN mode
    true, // enabled
    ethers.parseEther("1"), // minAmount
    ethers.parseEther("10000000000"), // maxAmount
    ethers.parseEther("1000000"), // dailyLimit
  )).wait();
  console.log("✅ Token configured:", lxonToken);

  // Set peer bridge (LXON Chain)
  console.log("\nSetting peer bridge (LXON Chain)...");
  const lxonChainId = 724;
  const lxonBridge = "0x692D0047323034514686eF57edFC26DBBa53F87B"; // Existing bridge
  await (await bridge.setPeerBridge(lxonChainId, lxonBridge)).wait();
  console.log("✅ Peer bridge set:", lxonBridge);

  console.log("\n✅✅✅ Polygon Bridge Deployment Complete ✅✅✅");
  console.log("\nBridge Address:", bridgeAddress);
  console.log("Chain ID:", chainId);
  console.log("Admin:", deployer.address);
  console.log("\nToken:", lxonToken);
  console.log("Peer Bridge (LXON Chain):", lxonBridge);
  
  console.log("\nNext: Set peer bridge on LXON Chain to point to this Polygon bridge");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
