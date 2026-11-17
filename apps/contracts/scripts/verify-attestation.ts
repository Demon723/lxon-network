import { ethers } from "hardhat";

async function main() {
  console.log("🔍 MultiSigAttester Verification Tool");

  // Get MultiSigAttester address
  const attesterAddress = process.env.MULTISIG_ATTESTER || "0x8E5d97D117cadA19c695cd529b79d8229637dfBD";
  console.log("MultiSigAttester:", attesterAddress);

  // Connect to attester contract
  const attester = await ethers.getContractAt("MultiSigAttester", attesterAddress);

  // Example attestation parameters (replace with actual values)
  const attestationId = process.env.ATTESTATION_ID || ethers.keccak256(ethers.toUtf8Bytes("TEST_ATTESTATION"));
  const validator = process.env.VALIDATOR || "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";
  const messageHash = process.env.MESSAGE_HASH || ethers.keccak256(ethers.toUtf8Bytes("TEST_MESSAGE"));
  const valid = process.env.VALID === "false" ? false : true;
  const timestamp = parseInt(process.env.TIMESTAMP || Math.floor(Date.now() / 1000).toString());

  // Attester addresses (from deployment)
  const attesterAddresses = [
    "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27",
    "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3",
    "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"
  ];

  // Signature components (replace with actual signed values)
  const rs = [
    process.env.R1 || "0x0000000000000000000000000000000000000000000000000000000000000000",
    process.env.R2 || "0x0000000000000000000000000000000000000000000000000000000000000000"
  ];
  const ss = [
    process.env.S1 || "0x0000000000000000000000000000000000000000000000000000000000000000",
    process.env.S2 || "0x0000000000000000000000000000000000000000000000000000000000000000"
  ];
  const vs = [
    parseInt(process.env.V1 || "27"),
    parseInt(process.env.V2 || "28")
  ];

  console.log("\nAttestation Parameters:");
  console.log("Attestation ID:", attestationId);
  console.log("Validator:", validator);
  console.log("Message Hash:", messageHash);
  console.log("Valid:", valid);
  console.log("Timestamp:", timestamp);
  console.log("Attesters:", attesterAddresses);
  console.log("Signature Count:", attesterAddresses.length);

  // Check if attestation is already used
  const isUsed = await attester.isAttestationUsed(attestationId);
  console.log("\nAttestation Already Used:", isUsed);

  if (isUsed) {
    console.log("⚠️  This attestation has already been used (replay protection)");
    return;
  }

  // Verify the attestation
  console.log("\nVerifying attestation...");
  try {
    const result = await attester.verifyMultiSigAttestation(
      attestationId,
      validator,
      messageHash,
      valid,
      timestamp,
      attesterAddresses,
      rs,
      ss,
      vs
    );

    console.log("✅ Attestation verified successfully!");
    console.log("Result:", result);
  } catch (error: any) {
    console.log("❌ Attestation verification failed");
    console.log("Error:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
