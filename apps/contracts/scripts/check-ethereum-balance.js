const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  console.log("=== Check Ethereum Wallet Balance ===\n");

  const rpcUrl = process.env.MAINNET_RPC_URL;
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

  console.log("RPC URL:", rpcUrl);
  console.log("Deployer Address:", "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27");

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("\n=== Checking Balance ===");
  const balance = await provider.getBalance(wallet.address);
  console.log("ETH Balance:", ethers.formatEther(balance), "ETH");

  // Estimate gas cost for bridge deployment (~3M gas at 20 gwei = 0.06 ETH)
  const estimatedGasCost = ethers.parseEther("0.1");
  console.log("Estimated deployment cost: ~0.1 ETH");
  console.log("Current balance:", ethers.formatEther(balance), "ETH");

  if (balance < estimatedGasCost) {
    console.log("\n❌ Insufficient ETH balance for deployment");
    console.log("Need at least 0.1 ETH for gas");
    console.log("Current:", ethers.formatEther(balance), "ETH");
    console.log("Short by:", ethers.formatEther(estimatedGasCost - balance), "ETH");
  } else {
    console.log("\n✅ Sufficient ETH balance for deployment");
    console.log("Can proceed with Ethereum bridge deployment");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
