import { ethers } from "ethers";

async function main() {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  const rpcUrl = "https://polygon.drpc.org";

  console.log("Deploying to Polygon using ethers.js directly...");
  console.log("RPC:", rpcUrl);
  
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
  
  console.log("\nDeploying contract...");
  const contract = await factory.deploy(137);
  
  console.log("Transaction hash:", contract.deploymentTransaction().hash);
  console.log("Waiting for confirmation (may take 2-5 minutes)...");
  
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log("\n✅ Deployed successfully!");
  console.log("Contract address:", address);
  
  // Verify
  console.log("\nVerifying deployment...");
  const chainId = await contract.chainId();
  const admin = await contract.admin();
  console.log("Chain ID:", chainId.toString());
  console.log("Admin:", admin);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
  });
