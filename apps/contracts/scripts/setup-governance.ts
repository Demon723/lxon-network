import { ethers } from "hardhat";

async function main() {
  console.log("Setting up LXON Settlement Asset Governance Roles...");

  const [deployer] = await ethers.getSigners();
  const contractAddress = "0xe801E058B4C9f77DD60980a80F7607a50AfE1799";
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const contract = LXONSettlementAsset.attach(contractAddress);

  console.log("Contract Address:", contractAddress);
  console.log("Deployer Address:", deployer.address);

  // Role hashes
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));

  // Get addresses from environment or use deployed multi-sig addresses
  const validatorMultiSig = process.env.VALIDATOR_MULTISIG || "0x99801A78639975D448EEb2f8a807738DC8Df67Dc";
  const oracleAddress = process.env.ORACLE_ADDRESS || deployer.address;
  const guardianMultiSig = process.env.GUARDIAN_MULTISIG || "0xbC18D2886EbeFEe91F6E820114b1D976F1be8330";

  console.log("\nGranting MINT_ROLE to validator multi-sig:", validatorMultiSig);
  const mintTx = await contract.grantRole(MINT_ROLE, validatorMultiSig);
  await mintTx.wait();
  console.log("✓ MINT_ROLE granted");

  console.log("\nGranting ORACLE_ROLE to oracle address:", oracleAddress);
  const oracleTx = await contract.grantRole(ORACLE_ROLE, oracleAddress);
  await oracleTx.wait();
  console.log("✓ ORACLE_ROLE granted");

  console.log("\nGranting GUARDIAN_ROLE to guardian multi-sig:", guardianMultiSig);
  const guardianTx = await contract.grantRole(GUARDIAN_ROLE, guardianMultiSig);
  await guardianTx.wait();
  console.log("✓ GUARDIAN_ROLE granted");

  console.log("\nGovernance Roles Setup Complete!");
  console.log("==================================");
  console.log("Contract:", contractAddress);
  console.log("MINT_ROLE:", validatorMultiSig);
  console.log("ORACLE_ROLE:", oracleAddress);
  console.log("GUARDIAN_ROLE:", guardianMultiSig);
  console.log("==================================");

  console.log("\nNext Steps:");
  console.log("1. Create 3-of-5 validator multi-sig wallet");
  console.log("2. Create 2-of-5 guardian multi-sig wallet");
  console.log("3. Set up oracle address for attestations");
  console.log("4. Re-run this script with actual addresses");
  console.log("5. Set initial reserve ceiling via updateCeiling()");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });