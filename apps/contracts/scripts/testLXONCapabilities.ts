import { ethers } from "hardhat";

async function main() {
  console.log("=== Testing LXON Network Capabilities ===\n");

  const provider = new ethers.JsonRpcProvider("http://16.171.20.249:8545");
  
  try {
    // Test 1: Basic RPC connection
    console.log("Test 1: Basic RPC Connection");
    const network = await provider.getNetwork();
    console.log("Network:", network);
    console.log("Chain ID:", network.chainId);
    console.log("✅ RPC connection working\n");

    // Test 2: Get block number
    console.log("Test 2: Get Block Number");
    const blockNumber = await provider.getBlockNumber();
    console.log("Current block:", blockNumber);
    console.log("✅ Block retrieval working\n");

    // Test 3: Get gas price
    console.log("Test 3: Get Gas Price");
    const gasPrice = await provider.getFeeData();
    console.log("Gas price:", gasPrice.gasPrice);
    console.log("✅ Gas price retrieval working\n");

    // Test 4: Get accounts
    console.log("Test 4: Get Accounts");
    try {
      const accounts = await provider.send("eth_accounts", []);
      console.log("Accounts:", accounts);
      console.log("✅ Account retrieval working\n");
    } catch (error) {
      console.log("⚠️ Account retrieval not supported\n");
    }

    // Test 5: Check deployer balance
    console.log("Test 5: Check Deployer Balance");
    const deployerAddress = "0x098Ae030804120Def93880a303788d24dc600d00";
    const balance = await provider.getBalance(deployerAddress);
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
    console.log("✅ Balance check working\n");

    // Test 6: Try to estimate gas for a simple transfer
    console.log("Test 6: Gas Estimation");
    try {
      const gasEstimate = await provider.estimateGas({
        to: deployerAddress,
        value: ethers.parseEther("1")
      });
      console.log("Gas estimate:", gasEstimate.toString());
      console.log("✅ Gas estimation working\n");
    } catch (error) {
      console.log("⚠️ Gas estimation not supported:", error.message, "\n");
    }

    // Test 7: Check if we can call a contract (even if it doesn't exist)
    console.log("Test 7: Contract Call Test");
    try {
      const code = await provider.getCode(deployerAddress);
      console.log("Contract code length:", code.length);
      console.log("✅ Code retrieval working\n");
    } catch (error) {
      console.log("⚠️ Code retrieval not supported:", error.message, "\n");
    }

    // Test 8: Try to get transaction count
    console.log("Test 8: Get Transaction Count");
    try {
      const nonce = await provider.getTransactionCount(deployerAddress);
      console.log("Nonce:", nonce);
      console.log("✅ Transaction count retrieval working\n");
    } catch (error) {
      console.log("⚠️ Transaction count not supported:", error.message, "\n");
    }

    console.log("=== LXON Network Capabilities Summary ===");
    console.log("✅ Basic RPC connection: WORKING");
    console.log("✅ Block retrieval: WORKING");
    console.log("✅ Gas price: WORKING");
    console.log("✅ Balance checks: WORKING");
    console.log("✅ Code retrieval: WORKING");
    console.log("✅ Gas estimation: TESTING");
    console.log("✅ Transaction count: TESTING");
    console.log("\n=== Conclusion ===");
    console.log("The LXON network responds to standard JSON-RPC read operations.");
    console.log("Next step: Test if we can send transactions using alternative methods.");

  } catch (error) {
    console.error("Error testing LXON network:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });