import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔐 Simplified Attestation Test");
  console.log("");

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const oneBPrivateKey = process.env.LXON_1B_PRIVATE_KEY;
  
  if (!deployerPrivateKey || !oneBPrivateKey) {
    throw new Error("Missing private keys for attesters");
  }

  const deployer = new ethers.Wallet(deployerPrivateKey);
  const oneBWallet = new ethers.Wallet(oneBPrivateKey);

  console.log("Attesters:");
  console.log("  1. Deployer:", deployer.address);
  console.log("  2. 1B Wallet:", oneBWallet.address);

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
  console.log("  Timestamp:", timestamp);

  // Generate signatures using 1B wallet instead of founder
  const attesterAddresses = [deployer.address, oneBWallet.address];
  const rs: string[] = [];
  const ss: string[] = [];
  const vs: number[] = [];

  console.log("\nGenerating signatures...");

  for (const attester of [deployer, oneBWallet]) {
    const messageHashForSig = ethers.keccak256(
      ethers.solidityPacked(
        ["bytes32", "address", "bytes32", "bool", "uint256", "address"],
        [transferId, validator, messageHash, valid, timestamp, attester.address]
      )
    );

    const signature = await attester.signMessage(ethers.getBytes(messageHashForSig));
    const sig = ethers.Signature.from(signature);
    
    rs.push(sig.r);
    ss.push(sig.s);
    vs.push(sig.v);

    console.log(`  ${attester.address.substring(0, 8)}...: Signed ✅`);
  }

  console.log("\n✅ Signatures collected");

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
