import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔐 Submitting Attestation with Threshold 1");
  console.log("");

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  if (!deployerPrivateKey) {
    throw new Error("No private key found in environment variables");
  }

  const deployer = new ethers.Wallet(deployerPrivateKey);

  console.log("Attester:");
  console.log("  Deployer:", deployer.address);
  console.log("  Threshold: 1 (reduced for testing)");

  // Transfer details
  const transferId = "0x9b4f18400dc33a6be2cf584fb69502105c44a3f3b28afa13d7a9eaf52ed4abcf";
  const validator = "0x692D0047323034514686eF57edFC26DBBa53F87B";
  const messageHash = ethers.keccak256(
    ethers.toUtf8Bytes("transfer-to-polygon-100-lxon")
  );
  const valid = true;
  const timestamp = Math.floor(Date.now() / 1000);

  console.log("\nTransfer Details:");
  console.log("  Transfer ID:", transferId);
  console.log("  Validator:", validator);
  console.log("  Message Hash:", messageHash);
  console.log("  Timestamp:", timestamp);

  // Generate single signature from deployer
  const attesterAddresses = [deployer.address];
  const rs: string[] = [];
  const ss: string[] = [];
  const vs: number[] = [];

  console.log("\nGenerating signature from deployer...");

  const messageHashForSig = ethers.keccak256(
    ethers.solidityPacked(
      ["bytes32", "address", "bytes32", "bool", "uint256", "address"],
      [transferId, validator, messageHash, valid, timestamp, deployer.address]
    )
  );

  const signature = await deployer.signMessage(ethers.getBytes(messageHashForSig));
  const sig = ethers.Signature.from(signature);
  
  rs.push(sig.r);
  ss.push(sig.s);
  vs.push(sig.v);

  console.log("  Deployer: Signed ✅");

  console.log("\n✅ Signature collected");

  // Submit to MultiSigAttester
  const multiSigAttesterAddress = "0x8E5d97D117cadA19c695cd529b79d8229637dfBD";
  const multiSigAttester = await ethers.getContractAt("MultiSigAttester", multiSigAttesterAddress);

  console.log("\nSubmitting attestation...");
  
  try {
    const verifyTx = await multiSigAttester.verifyMultiSigAttestation(
      transferId,
      validator,
      messageHash,
      valid,
      timestamp,
      attesterAddresses,
      rs,
      ss,
      vs
    );

    console.log("Transaction hash:", verifyTx.hash);
    await verifyTx.wait();
    console.log("✅ Attestation verified successfully!");

    console.log("\n=== Attestation Complete ===");
    console.log("Status: Attested (1 signature with threshold 1)");
    console.log("Next: Complete transfer on Polygon bridge");

  } catch (error: any) {
    console.log("❌ Attestation failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
