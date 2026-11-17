import { ethers } from "ethers";

async function main() {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  const rpcUrl = "https://polygon.drpc.org";
  
  console.log("Deploying with EIP-1559 (priority fee) for faster confirmation...");
  
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log("Deployer:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "MATIC");
  
  // Read bytecode
  const fs = require("fs");
  const artifact = JSON.parse(fs.readFileSync("./artifacts/contracts/LxonBridgeSimpleV2.sol/LxonBridgeSimpleV2.json", "utf8"));
  
  const factory = new ethers.ContractFactory(
    artifact.abi,
    artifact.bytecode,
    wallet
  );
  
  // Get current fee data
  const feeData = await provider.getFeeData();
  console.log("Current gas price:", ethers.formatUnits(feeData.gasPrice || 0n, "gwei"), "gwei");
  
  // Use EIP-1559 with high priority fee
  const maxFeePerGas = ethers.parseUnits("500", "gwei"); // High max fee
  const maxPriorityFeePerGas = ethers.parseUnits("100", "gwei"); // High priority
  
  console.log("Using maxFeePerGas:", ethers.formatUnits(maxFeePerGas, "gwei"), "gwei");
  console.log("Using maxPriorityFeePerGas:", ethers.formatUnits(maxPriorityFeePerGas, "gwei"), "gwei");
  
  console.log("\nDeploying contract...");
  const contract = await factory.deploy(137, {
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    gasLimit: 5000000
  });
  
  console.log("Transaction hash:", contract.deploymentTransaction().hash);
  console.log("Waiting for confirmation...");
  
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log("\n✅ Deployed successfully!");
  console.log("Contract address:", address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
  });
