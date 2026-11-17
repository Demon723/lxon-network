import { ethers } from "ethers";

async function main() {
  console.log("🚀 Deploying LxonBridgeSimpleV2 on LXON Chain (Direct)");
  console.log("========================================================\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const provider = new ethers.JsonRpcProvider("http://13.61.177.64:8546");
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log("Deployer:", wallet.address);
  console.log("Balance:", ethers.formatEther(await provider.getBalance(wallet.address)), "ETH\n");

  // LXON Chain ID
  const chainId = 724;
  
  console.log("Deploying LxonBridgeSimpleV2...");
  const bridgeArtifact = require("../artifacts/contracts/LxonBridgeSimpleV2.sol/LxonBridgeSimpleV2.json");
  const Bridge = new ethers.ContractFactory(bridgeArtifact.abi, bridgeArtifact.bytecode, wallet);
  const bridge = await Bridge.deploy(chainId, {
    gasLimit: 2000000,
    gasPrice: ethers.parseUnits("1", "gwei"),
  });
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  console.log("✅ Bridge deployed:", bridgeAddress);

  // Set admin (deployer)
  console.log("\nSetting admin...");
  const setAdminTx = await (bridge as any).setAdmin(wallet.address);
  await setAdminTx.wait();
  console.log("✅ Admin set:", wallet.address);

  // Configure token (LXON on LXON Chain)
  console.log("\nConfiguring LXON token...");
  const lxonToken = "0xc0177883C0c662870855660495C697385FE040f5";
  const configureTx = await (bridge as any).configureToken(
    lxonToken,
    2, // MINT_BURN mode
    true, // enabled
    ethers.parseEther("1"), // minAmount
    ethers.parseEther("10000000000"), // maxAmount
    ethers.parseEther("1000000"), // dailyLimit
  );
  await configureTx.wait();
  console.log("✅ Token configured:", lxonToken);

  console.log("\n✅✅✅ LXON Chain Bridge Deployment Complete ✅✅✅");
  console.log("\nBridge Address:", bridgeAddress);
  console.log("Chain ID:", chainId);
  console.log("Admin:", wallet.address);
  console.log("\nToken:", lxonToken);
  
  console.log("\nNext: Set peer bridge for Polygon");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
