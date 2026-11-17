import { ethers } from "hardhat";

async function main() {
  console.log("Setting Initial Reserve Ceiling for LXON Settlement Asset...");

  const [deployer] = await ethers.getSigners();
  const contractAddress = "0xe801E058B4C9f77DD60980a80F7607a50AfE1799";
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const contract = LXONSettlementAsset.attach(contractAddress);

  console.log("Contract Address:", contractAddress);
  console.log("Deployer Address:", deployer.address);

  // Initial reserve ceiling: 1,000,000 USD = 100,000,000 cents
  const initialReserveCents = 100000000; // $1,000,000 in cents
  const attestationHash = ethers.keccak256(ethers.toUtf8Bytes("initial-attestation-placeholder"));

  console.log("\nSetting initial reserve ceiling to $1,000,000 USD");
  const tx = await contract.updateCeiling(initialReserveCents, attestationHash);
  await tx.wait();

  console.log("✓ Reserve ceiling updated");
  console.log("  Amount: $1,000,000 USD");
  console.log("  Cents:", initialReserveCents.toString());
  console.log("  Attestation Hash:", attestationHash);

  console.log("\nInitial Reserve Ceiling Set!");
  console.log("==================================");
  console.log("Contract:", contractAddress);
  console.log("Reserve Ceiling: $1,000,000 USD");
  console.log("Max Supply: 1,000,000 LXON");
  console.log("==================================");

  console.log("\nNext Steps:");
  console.log("1. Get first independent attestation from accounting firm");
  console.log("2. Update ceiling with real attestation hash");
  console.log("3. Begin minting against confirmed deposits");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });