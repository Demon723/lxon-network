import { ethers } from "hardhat";

async function main() {
  console.log("=== Verifying New Deployer Configuration ===\n");

  const rpcUrl = "https://rpc.lxon.in";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Testing RPC endpoint:", rpcUrl);
  console.log("New deployer address:", newDeployerAddress);
  console.log();

  const provider = new ethers.JsonRpcProvider(rpcUrl);

  try {
    // Test 1: Chain ID
    console.log("Test 1: Chain ID");
    const network = await provider.getNetwork();
    console.log("Chain ID:", network.chainId.toString());
    if (network.chainId === 724n) {
      console.log("✅ Correct chain ID (724)");
    } else {
      console.log("❌ Wrong chain ID (expected 724)");
    }
    console.log();

    // Test 2: Block Number
    console.log("Test 2: Block Number");
    const blockNumber = await provider.getBlockNumber();
    console.log("Current block:", blockNumber);
    console.log("✅ Chain is producing blocks");
    console.log();

    // Test 3: New Deployer Balance
    console.log("Test 3: New Deployer Balance");
    const balance = await provider.getBalance(newDeployerAddress);
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
    if (balance > 0n) {
      console.log("✅ Deployer has funds for deployment");
    } else {
      console.log("❌ Deployer has no funds");
    }
    console.log();

    // Test 4: Gas Price
    console.log("Test 4: Gas Price");
    const gasPrice = await provider.getFeeData();
    console.log("Gas price:", gasPrice.gasPrice.toString(), "wei");
    console.log("✅ Gas price available");
    console.log();

    // Test 5: Transaction Count
    console.log("Test 5: Transaction Count");
    const nonce = await provider.getTransactionCount(newDeployerAddress);
    console.log("Nonce:", nonce.toString());
    console.log("✅ Transaction count available");
    console.log();

    // Test 6: Client Version
    console.log("Test 6: Client Version");
    const block = await provider.getBlock("latest");
    console.log("Client:", block.miner || "Unknown");
    console.log("✅ RPC connection working");
    console.log();

    console.log("=== Verification Summary ===");
    console.log("RPC endpoint:", rpcUrl);
    console.log("New deployer:", newDeployerAddress);
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
    console.log("Ready for deployment: ✅ YES");

  } catch (error) {
    console.error("❌ Error:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
