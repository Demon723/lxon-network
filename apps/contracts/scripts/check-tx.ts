import { ethers } from "hardhat";

async function main() {
  const txHash = "0x958202937c4f87bfe17cbe1a92df524255c4c79c781a89e0e97b2aff0c18a097";
  
  console.log("Checking transaction:", txHash);
  
  const tx = await ethers.provider.getTransaction(txHash);
  console.log("Transaction:", tx ? "Found" : "Not found");
  
  if (tx) {
    console.log("From:", tx.from);
    console.log("To:", tx.to);
    console.log("Value:", ethers.formatEther(tx.value), "MATIC");
    console.log("Gas Price:", ethers.formatUnits(tx.gasPrice || 0, "gwei"), "gwei");
  }
  
  const receipt = await ethers.provider.getTransactionReceipt(txHash);
  console.log("Receipt:", receipt ? "Confirmed" : "Pending");
  
  if (receipt) {
    console.log("Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("Block:", receipt.blockNumber);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
