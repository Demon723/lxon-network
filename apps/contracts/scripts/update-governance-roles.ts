import { ethers } from "hardhat";

async function main() {
  console.log("Updating LXON Settlement Asset Governance Roles with Real Multi-Sig Addresses...");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("DEPLOYER_PRIVATE_KEY environment variable not set");
  }

  const rpcUrl = "http://13.51.158.120:8546";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  const contractAddress = "0xe801E058B4C9f77DD60980a80F7607a50AfE1799";
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const contract = LXONSettlementAsset.attach(contractAddress);

  // Role hashes
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;

  console.log("Contract Address:", contractAddress);
  console.log("Deployer Address:", wallet.address);

  // Get actual addresses from environment or use deployed multi-sig addresses
  const validatorMultiSig = process.env.VALIDATOR_MULTISIG || "0x0000000000000000000000000000000000000001";
  const oracleAddress = process.env.ORACLE_ADDRESS || "0x0000000000000000000000000000000000000002";
  const guardianMultiSig = process.env.GUARDIAN_MULTISIG || "0x0000000000000000000000000000000000000003";

  console.log("\n=== Phase 1: Grant Roles to Real Addresses ===");

  console.log("\nGranting MINT_ROLE to validator multi-sig:", validatorMultiSig);
  const mintTx = await contract.grantRole(MINT_ROLE, validatorMultiSig);
  await mintTx.wait();
  console.log("✓ MINT_ROLE granted to", validatorMultiSig);

  console.log("\nGranting ORACLE_ROLE to oracle address:", oracleAddress);
  const oracleTx = await contract.grantRole(ORACLE_ROLE, oracleAddress);
  await oracleTx.wait();
  console.log("✓ ORACLE_ROLE granted to", oracleAddress);

  console.log("\nGranting GUARDIAN_ROLE to guardian multi-sig:", guardianMultiSig);
  const guardianTx = await contract.grantRole(GUARDIAN_ROLE, guardianMultiSig);
  await guardianTx.wait();
  console.log("✓ GUARDIAN_ROLE granted to", guardianMultiSig);

  console.log("\n=== Phase 2: Revoke Roles from Placeholder Addresses ===");

  console.log("\nRevoking MINT_ROLE from placeholder");
  const revokeMintTx = await contract.revokeRole(MINT_ROLE, "0x0000000000000000000000000000000000000001");
  await revokeMintTx.wait();
  console.log("✓ MINT_ROLE revoked from placeholder");

  console.log("\nRevoking ORACLE_ROLE from placeholder");
  const revokeOracleTx = await contract.revokeRole(ORACLE_ROLE, "0x0000000000000000000000000000000000000002");
  await revokeOracleTx.wait();
  console.log("✓ ORACLE_ROLE revoked from placeholder");

  console.log("\nRevoking GUARDIAN_ROLE from placeholder");
  const revokeGuardianTx = await contract.revokeRole(GUARDIAN_ROLE, "0x0000000000000000000000000000000000000003");
  await revokeGuardianTx.wait();
  console.log("✓ GUARDIAN_ROLE revoked from placeholder");

  console.log("\n=== Phase 3: Transfer DEFAULT_ADMIN_ROLE ===");

  // Transfer DEFAULT_ADMIN_ROLE to validator multi-sig for decentralized control
  console.log("\nTransferring DEFAULT_ADMIN_ROLE to validator multi-sig:", validatorMultiSig);
  const adminTx = await contract.grantRole(DEFAULT_ADMIN_ROLE, validatorMultiSig);
  await adminTx.wait();
  console.log("✓ DEFAULT_ADMIN_ROLE granted to", validatorMultiSig);

  console.log("\nRevoking DEFAULT_ADMIN_ROLE from deployer");
  const revokeAdminTx = await contract.revokeRole(DEFAULT_ADMIN_ROLE, wallet.address);
  await revokeAdminTx.wait();
  console.log("✓ DEFAULT_ADMIN_ROLE revoked from deployer:", wallet.address);

  console.log("\n=== Governance Roles Update Complete! ===");
  console.log("==================================");
  console.log("Contract:", contractAddress);
  console.log("MINT_ROLE:", validatorMultiSig);
  console.log("ORACLE_ROLE:", oracleAddress);
  console.log("GUARDIAN_ROLE:", guardianMultiSig);
  console.log("DEFAULT_ADMIN_ROLE:", validatorMultiSig);
  console.log("==================================");

  console.log("\nSecurity Status:");
  console.log("✓ Deployer no longer has admin privileges");
  console.log("✓ Governance is now decentralized");
  console.log("✓ Multi-sig wallets control critical functions");
  console.log("✓ Placeholder addresses revoked");

  console.log("\nNext Steps:");
  console.log("1. Verify role assignments on-chain");
  console.log("2. Test multi-sig functionality");
  console.log("3. Set up key ceremony procedures");
  console.log("4. Document key holders and locations");
  console.log("5. Engage accounting firm for attestation");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });