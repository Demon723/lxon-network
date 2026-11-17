import { ethers } from "ethers";

async function main() {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  
  // Try multiple RPCs
  const rpcUrls = [
    "https://rpc.ankr.com/polygon",
    "https://polygon.api.0x.org",
    "https://polygon-bor.publicnode.com"
  ];
  
  for (const rpcUrl of rpcUrls) {
    try {
      console.log(`\nTrying RPC: ${rpcUrl}`);
      
      const provider = new ethers.JsonRpcProvider(rpcUrl);
      const wallet = new ethers.Wallet(privateKey, provider);
      
      // Test connection
      const chainId = await provider.getNetwork();
      console.log("Chain ID:", chainId.chainId.toString());
      
      const balance = await provider.getBalance(wallet.address);
      console.log("Balance:", ethers.formatEther(balance), "MATIC");
      
      if (balance < ethers.parseEther("2")) {
        console.log("Insufficient balance, trying next RPC...");
        continue;
      }
      
      // Read bytecode
      const fs = require("fs");
      const artifact = JSON.parse(fs.readFileSync("./artifacts/contracts/LxonBridgeSimpleV2.sol/LxonBridgeSimpleV2.json", "utf8"));
      
      const factory = new ethers.ContractFactory(
        artifact.abi,
        artifact.bytecode,
        wallet
      );
      
      // Get fee data
      const feeData = await provider.getFeeData();
      const gasPrice = feeData.gasPrice || ethers.parseUnits("50", "gwei");
      
      console.log("Gas price:", ethers.formatUnits(gasPrice, "gwei"), "gwei");
      
      console.log("\nDeploying contract...");
      const contract = await factory.deploy(137, {
        gasLimit: 5000000,
        gasPrice: gasPrice
      });
      
      console.log("Transaction hash:", contract.deploymentTransaction().hash);
      console.log("Waiting for confirmation...");
      
      await contract.waitForDeployment();
      
      const address = await contract.getAddress();
      console.log("\n✅ Deployed successfully!");
      console.log("Contract address:", address);
      console.log("RPC used:", rpcUrl);
      
      return;
      
    } catch (error) {
      console.log("Error with this RPC:", error.message);
      continue;
    }
  }
  
  console.log("\n❌ All RPCs failed");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
  });
