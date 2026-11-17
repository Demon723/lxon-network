import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const txHash = "0xfb606e186c1ae37e942ace07bdf79e64090eb7a993a78c28a0124a34de5cbc72";

  console.log("Checking transaction:", txHash);

  const provider = await ethers.provider;
  const tx = await provider.getTransaction(txHash);
  const receipt = await provider.getTransactionReceipt(txHash);

  console.log("\n=== Transaction Details ===");
  console.log("From:", tx.from);
  console.log("To:", tx.to);
  console.log("Value:", ethers.formatEther(tx.value), "ETH");
  console.log("Status:", receipt.status === 1 ? "✅ Success" : "❌ Failed");
  console.log("Block:", receipt.blockNumber);
  console.log("Gas used:", receipt.gasUsed.toString());

  // Check if it's a token transfer
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const newDeployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  // Check if transaction was to LXON contract (ERC20 transfer)
  if (tx.to.toLowerCase() === LXON_ADDRESS.toLowerCase()) {
    console.log("\n✅ This is an ERC20 token transfer to LXON contract");
    
    // Parse the input data
    const transferInterface = new ethers.Interface([
      "function transfer(address to, uint256 amount)"
    ]);
    
    try {
      const parsed = transferInterface.parseTransaction({ data: tx.data });
      console.log("\n=== Transfer Details ===");
      console.log("To:", parsed.args[0]);
      console.log("Amount:", ethers.formatUnits(parsed.args[1], 6), "LXON");
    } catch (e) {
      console.log("Could not parse transfer data");
    }
  } else {
    console.log("\n❌ This is NOT an ERC20 token transfer");
    console.log("Transaction was to:", tx.to);
    console.log("LXON contract:", LXON_ADDRESS);
  }

  // Check balance using raw call
  const balanceOfSelector = "0x70a08231";
  const newCallData = balanceOfSelector + newDeployerAddress.slice(2).padStart(64, '0');
  const newBalance = await provider.call({
    to: LXON_ADDRESS,
    data: newCallData
  });
  console.log("\n=== New Deployer Balance ===");
  console.log("Address:", newDeployerAddress);
  console.log("LXON balance:", ethers.formatUnits(newBalance, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
