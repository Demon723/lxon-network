import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔧 Restoring MultiSigAttester Threshold to 2");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const [signer] = await ethers.getSigners();
  console.log("Signer address:", signer.address);

  const multiSigAttesterAddress = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD";
  const multiSigAttester = await ethers.getContractAt("MultiSigAttester", multiSigAttesterAddress);

  console.log("\nCurrent threshold: 1");
  console.log("Restoring threshold to 2...");

  try {
    const setThresholdTx = await multiSigAttester.setThreshold(2);
    console.log("Transaction hash:", setThresholdTx.hash);
    await setThresholdTx.wait();
    console.log("✅ Threshold restored to 2");

    const newThreshold = await multiSigAttester.threshold();
    console.log("New threshold:", newThreshold.toString());

    console.log("\n=== Threshold Restored ===");
    console.log("MultiSigAttester is back to production settings");

  } catch (error: any) {
    console.log("❌ Threshold update failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
