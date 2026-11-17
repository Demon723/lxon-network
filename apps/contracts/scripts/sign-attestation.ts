import { ethers } from "hardhat";
import { MultiSigAttester } from "../typechain-types";

async function main() {
  console.log("🔐 MultiSigAttester Signing Tool");

  // Get attester private key from environment
  const privateKey = process.env.ATTESTER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("ATTESTER_PRIVATE_KEY environment variable not set");
  }

  const wallet = new ethers.Wallet(privateKey);
  console.log("Attester Address:", wallet.address);

  // Get MultiSigAttester address
  const attesterAddress = process.env.MULTISIG_ATTESTER || "0x8E5d97D117cadA19c695cd529b79d8229637dfBD";
  console.log("MultiSigAttester:", attesterAddress);

  // Connect to attester contract
  const attester = await ethers.getContractAt("MultiSigAttester", attesterAddress);

  // Get current nonce
  const nonce = await attester.getNonce(wallet.address);
  console.log("Current Nonce:", nonce.toString());

  // Example attestation parameters
  const attestationId = ethers.keccak256(ethers.toUtf8Bytes("TEST_ATTESTATION"));
  const validator = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";
  const messageHash = ethers.keccak256(ethers.toUtf8Bytes("TEST_MESSAGE"));
  const valid = true;
  const timestamp = Math.floor(Date.now() / 1000);

  console.log("\nAttestation Parameters:");
  console.log("Attestation ID:", attestationId);
  console.log("Validator:", validator);
  console.log("Message Hash:", messageHash);
  console.log("Valid:", valid);
  console.log("Timestamp:", timestamp);

  // Build message hash for signature
  const messageHashForSig = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "address", "bytes32", "bool", "uint256", "address"],
      [attestationId, validator, messageHash, valid, timestamp, wallet.address]
    )
  );

  console.log("Message Hash for Signature:", messageHashForSig);

  // Sign the message
  const signature = await wallet.signMessage(ethers.getBytes(messageHashForSig));
  console.log("Signature:", signature);

  // Parse signature
  const r = "0x" + signature.slice(2, 66);
  const s = "0x" + signature.slice(66, 130);
  const v = parseInt(signature.slice(130, 132), 16);

  console.log("\nSignature Components:");
  console.log("r:", r);
  console.log("s:", s);
  console.log("v:", v);

  console.log("\n✅ Attestation signed successfully!");
  console.log("\nTo verify this attestation on-chain, use the verify-attestation.ts script with:");
  console.log(`  Attestation ID: ${attestationId}`);
  console.log(`  Validator: ${validator}`);
  console.log(`  Message Hash: ${messageHash}`);
  console.log(`  Valid: ${valid}`);
  console.log(`  Timestamp: ${timestamp}`);
  console.log(`  Attester: ${wallet.address}`);
  console.log(`  r: ${r}`);
  console.log(`  s: ${s}`);
  console.log(`  v: ${v}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
