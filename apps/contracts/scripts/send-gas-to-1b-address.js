const { ethers } = require("ethers");
require("dotenv").config();

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_1B_ADDRESS = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Send Gas to LXON 1B Address ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deployer:", wallet.address);
  console.log("Target:", LXON_1B_ADDRESS);

  // Check deployer's native balance
  const deployerBalance = await provider.getBalance(wallet.address);
  console.log("Deployer native LXON:", ethers.formatEther(deployerBalance));

  // Check target's native balance
  const targetBalance = await provider.getBalance(LXON_1B_ADDRESS);
  console.log("Target native LXON:", ethers.formatEther(targetBalance));

  // Send 10 native LXON for gas
  const gasAmount = ethers.parseEther("10");
  console.log("\nSending 10 native LXON for gas...");

  if (deployerBalance < gasAmount) {
    console.log("❌ Insufficient native LXON");
    return;
  }

  try {
    const tx = await wallet.sendTransaction({
      to: LXON_1B_ADDRESS,
      value: gasAmount
    });
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Gas sent successfully");

    // Verify
    const newTargetBalance = await provider.getBalance(LXON_1B_ADDRESS);
    console.log("New target balance:", ethers.formatEther(newTargetBalance));
  } catch (error) {
    console.error("❌ Failed to send gas:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
