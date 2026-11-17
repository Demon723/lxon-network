import { ethers } from "hardhat";

async function main() {
  const txHash = "0x3c1d5acde625abc8c3813c4760ff869b116ca6e5408da5a588ac501338d2afe2";
  
  console.log("Checking mint transaction:", txHash);
  
  const receipt = await ethers.provider.getTransactionReceipt(txHash);
  console.log("Receipt:", receipt ? "Confirmed" : "Pending");
  
  if (receipt) {
    console.log("Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("Gas used:", receipt.gasUsed.toString());
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
