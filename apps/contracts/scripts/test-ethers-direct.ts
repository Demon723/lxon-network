import { ethers } from "ethers";

async function main() {
  console.log("Testing direct ethers.js deployment on Sepolia");
  console.log("===============================================\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error("No key in source. Set DEPLOYER_PRIVATE_KEY or PRIVATE_KEY in the environment.");
    process.exit(1);
  }
  const provider = new ethers.JsonRpcProvider("https://eth-sepolia.g.alchemy.com/v2/demo");
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Wallet:", wallet.address);
  console.log("Balance:", ethers.formatEther(await provider.getBalance(wallet.address)), "ETH\n");

  // Minimal contract bytecode (a simple contract that just returns true)
  const bytecode = "0x608060345f80fd5b80601157601f56f3";
  const abi = ["function isTrue() view returns (bool)"];

  console.log("Deploying minimal contract...");
  const factory = new ethers.ContractFactory(abi, bytecode, wallet);
  
  try {
    const contract = await factory.deploy({
      gasLimit: 100000,
      gasPrice: ethers.parseUnits("5", "gwei"),
    });
    console.log("Transaction hash:", contract.deploymentTransaction().hash);
    
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    console.log("✅ Contract deployed:", address);
  } catch (error) {
    console.error("❌ Deployment failed:");
    console.error(error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
