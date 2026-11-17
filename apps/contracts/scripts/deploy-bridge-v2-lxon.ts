import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LxonBridgeSimpleV2 on LXON Chain");
  console.log("===============================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  // LXON Chain ID
  const chainId = 724;
  
  console.log("Deploying LxonBridgeSimpleV2...");
  const Bridge = await ethers.getContractFactory("LxonBridgeSimpleV2");
  const bridge = await Bridge.deploy(chainId, {
    gasLimit: 2000000,
    gasPrice: ethers.parseUnits("1", "gwei"),
  });
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  console.log("✅ Bridge deployed:", bridgeAddress);

  // Set admin (deployer)
  console.log("\nSetting admin...");
  await (await bridge.setAdmin(deployer.address)).wait();
  console.log("✅ Admin set:", deployer.address);

  // Configure token (LXON on LXON Chain)
  console.log("\nConfiguring LXON token...");
  const lxonToken = "0xc0177883C0c662870855660495C697385FE040f5";
  await (await bridge.configureToken(
    lxonToken,
    2, // MINT_BURN mode
    true, // enabled
    ethers.parseEther("1"), // minAmount
    ethers.parseEther("10000000000"), // maxAmount
    ethers.parseEther("1000000"), // dailyLimit
  )).wait();
  console.log("✅ Token configured:", lxonToken);

  console.log("\n✅✅✅ LXON Chain Bridge Deployment Complete ✅✅✅");
  console.log("\nBridge Address:", bridgeAddress);
  console.log("Chain ID:", chainId);
  console.log("Admin:", deployer.address);
  console.log("\nToken:", lxonToken);
  
  console.log("\nNext: Set peer bridge for Polygon");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
