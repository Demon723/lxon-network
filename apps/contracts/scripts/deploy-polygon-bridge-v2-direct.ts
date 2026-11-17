import { ethers } from "hardhat";

async function main() {
  const polygonRPC = "https://polygon.drpc.org";
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  console.log("Using RPC:", polygonRPC);
  
  if (!privateKey) {
    throw new Error("DEPLOYER_PRIVATE_KEY not set in .env");
  }

  console.log("Deploying to Polygon...");
  console.log("RPC:", polygonRPC);
  
  const provider = new ethers.JsonRpcProvider(polygonRPC);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log("Deployer address:", wallet.address);
  
  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "MATIC");
  
  if (balance < ethers.parseEther("2")) {
    console.warn("⚠️ Warning: Low balance (< 2 MATIC)");
  }
  
  // Get deployer nonce
  const nonce = await provider.getTransactionCount(wallet.address, "pending");
  console.log("Nonce:", nonce);
  
  // Deploy contract
  console.log("\nDeploying LxonBridgeSimpleV2...");
  const Bridge = await ethers.getContractFactory("LxonBridgeSimpleV2");
  
  // Get current gas price and add 20% buffer
  const feeData = await provider.getFeeData();
  const gasPrice = feeData.gasPrice ? feeData.gasPrice * 120n / 100n : ethers.parseUnits("100", "gwei");
  
  console.log("Gas price:", ethers.formatUnits(gasPrice, "gwei"), "gwei");
  
  const bridge = await Bridge.connect(wallet).deploy(137, {
    nonce: nonce,
    gasLimit: 5000000,
    gasPrice: gasPrice
  });
  
  console.log("Transaction hash:", bridge.deploymentTransaction()?.hash);
  console.log("Waiting for confirmation...");
  
  await bridge.waitForDeployment();
  
  console.log("\n✅ Bridge deployed successfully!");
  console.log("Contract address:", await bridge.getAddress());
  console.log("Chain ID:", await bridge.chainId());
  console.log("Admin:", await bridge.admin());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
