import { ethers } from "hardhat";

async function main() {
  console.log("=== Verifying Geth RPC Endpoint ===\n");

  const rpcUrl = "https://rpc.lxon.in";
  const deployerAddress = "0x098Ae030804120Def93880a303788d24dc600d00";

  console.log("Testing RPC endpoint:", rpcUrl);
  console.log("Deployer address:", deployerAddress);
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
    if (blockNumber > 0) {
      console.log("✅ Chain is producing blocks");
    } else {
      console.log("⚠️ Chain is at genesis (block 0)");
    }
    console.log();

    // Test 3: Deployer Balance
    console.log("Test 3: Deployer Balance");
    const balance = await provider.getBalance(deployerAddress);
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
    if (balance > 0) {
      console.log("✅ Deployer has funds for deployment");
    } else {
      console.log("❌ Deployer has no funds - need to mine or fund");
    }
    console.log();

    // Test 4: Gas Price
    console.log("Test 4: Gas Price");
    const feeData = await provider.getFeeData();
    console.log("Gas price:", ethers.formatUnits(feeData.gasPrice || 0n, "gwei"), "gwei");
    console.log("✅ Gas price available");
    console.log();

    // Test 5: Gas Estimation
    console.log("Test 5: Gas Estimation");
    try {
      const gasEstimate = await provider.estimateGas({
        to: deployerAddress,
        value: ethers.parseEther("1")
      });
      console.log("Gas estimate:", gasEstimate.toString());
      console.log("✅ Gas estimation working");
    } catch (error) {
      console.log("⚠️ Gas estimation not supported");
    }
    console.log();

    // Test 6: Transaction Count
    console.log("Test 6: Transaction Count");
    const nonce = await provider.getTransactionCount(deployerAddress);
    console.log("Nonce:", nonce);
    console.log("✅ Transaction count available");
    console.log();

    // Test 7: Client Version
    console.log("Test 7: Client Version");
    try {
      const clientVersion = await provider.send("web3_clientVersion", []);
      console.log("Client:", clientVersion);
      if (clientVersion.toLowerCase().includes("geth")) {
        console.log("✅ Running Geth (good for deployment)");
      } else {
        console.log("⚠️ Not running Geth - may have deployment issues");
      }
    } catch (error) {
      console.log("⚠️ Client version not available");
    }
    console.log();

    console.log("=== Verification Summary ===");
    console.log("RPC endpoint:", rpcUrl);
    console.log("Chain ID:", network.chainId.toString());
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
    console.log("Ready for deployment:", balance > 0n ? "✅ YES" : "❌ NO (need funds)");
    console.log();

    if (balance > 0n) {
      console.log("🚀 Ready to deploy contracts!");
      console.log("Run: npm run deploy:fresh");
    } else {
      console.log("⚠️ Deployer needs funds before deployment");
      console.log("Options:");
      console.log("1. Wait for mining to produce blocks");
      console.log("2. Mine manually: geth attach http://16.171.20.249:8545");
      console.log("3. Send funds from another account");
    }

  } catch (error) {
    console.error("❌ RPC connection failed:", error.message);
    console.log();
    console.log("Troubleshooting:");
    console.log("1. Check if Geth is running: ssh ubuntu@16.171.20.249 'systemctl status geth-lxon'");
    console.log("2. Check firewall: ssh ubuntu@16.171.20.249 'sudo ufw status'");
    console.log("3. Check logs: ssh ubuntu@16.171.20.249 'journalctl -u geth-lxon -f'");
    console.log("4. Ensure Geth was deployed using: sudo bash /tmp/deploy-geth.sh");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });