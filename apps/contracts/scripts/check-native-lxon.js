const { ethers } = require("ethers");
require("dotenv").config");

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Check Native LXON Acquisition Options ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  // Check current native balance
  const nativeBalance = await provider.getBalance(wallet.address);
  console.log("Current native LXON:", ethers.formatEther(nativeBalance));

  // Check if this is a devnet/testnet with faucet capabilities
  const blockNumber = await provider.getBlockNumber();
  console.log("Current block:", blockNumber);

  // Try to check if there's a way to get native LXON
  console.log("\n=== Native LXON Acquisition ===");
  console.log("Native LXON cannot be minted like ERC20 tokens");
  console.log("It's obtained through:");
  console.log("1. Mining/validating on the network");
  console.log("2. Transfers from others");
  console.log("3. Buying from others");
  console.log("4. Faucets (if available)");

  console.log("\n=== Current Options ===");
  console.log("Option 1: If you control the network, you might have special privileges");
  console.log("Option 2: If this is a testnet, there might be a faucet");
  console.log("Option 3: Buy native LXON from someone who has it");
  console.log("Option 4: Accept current price with available resources");

  console.log("\n=== What Do You Want to Do? ===");
  console.log("A) Check if there's a faucet for native LXON");
  console.log("B) Try to mine/validate for native LXON");
  console.log("C) Accept current price of $0.257/LXON");
  console.log("D) Something else");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
