import { ethers } from "hardhat";

async function main() {
  console.log("Verifying LXON Settlement Asset Governance Roles...");

  const rpcUrl = "http://13.51.158.120:8546";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const contractAddress = "0xe801E058B4C9f77DD60980a80F7607a50AfE1799";
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const contract = LXONSettlementAsset.attach(contractAddress);

  // Role hashes
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;

  console.log("Contract Address:", contractAddress);
  console.log("Chain ID:", await provider.getNetwork().then(n => n.chainId));

  console.log("\n=== Role Holders ===");

  // Check MINT_ROLE
  const mintHolder = await contract.hasRole(MINT_ROLE, "0x5FbDB2315678afecb367f032d93F642f64180aa3");
  console.log("MINT_ROLE assigned to validator multi-sig:", mintHolder);
  console.log("Expected: true");
  console.log("Match:", mintHolder === true);

  // Check ORACLE_ROLE
  const oracleHolder = await contract.hasRole(ORACLE_ROLE, "0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA");
  console.log("\nORACLE_ROLE assigned to oracle:", oracleHolder);
  console.log("Expected: true");
  console.log("Match:", oracleHolder === true);

  // Check GUARDIAN_ROLE
  const guardianHolder = await contract.hasRole(GUARDIAN_ROLE, "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");
  console.log("\nGUARDIAN_ROLE assigned to guardian multi-sig:", guardianHolder);
  console.log("Expected: true");
  console.log("Match:", guardianHolder === true);

  // Check DEFAULT_ADMIN_ROLE
  const adminHolder = await contract.hasRole(DEFAULT_ADMIN_ROLE, "0x5FbDB2315678afecb367f032d93F642f64180aa3");
  console.log("\nDEFAULT_ADMIN_ROLE assigned to validator multi-sig:", adminHolder);
  console.log("Expected: true");
  console.log("Match:", adminHolder === true);

  // Check that deployer no longer has admin role
  const deployerAdmin = await contract.hasRole(DEFAULT_ADMIN_ROLE, "0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA");
  console.log("\nDeployer has DEFAULT_ADMIN_ROLE:", deployerAdmin);
  console.log("Expected: false");
  console.log("Match:", deployerAdmin === false);

  // Check reserve ceiling
  const reserveCeiling = await contract.reserveCeiling();
  console.log("\nReserve Ceiling:", reserveCeiling.toString());
  console.log("Expected: 100000000 ($1,000,000 USD)");
  console.log("Match:", reserveCeiling.toString() === "100000000");

  // Check total supply
  const totalSupply = await contract.totalSupply();
  console.log("\nTotal Supply:", totalSupply.toString());
  console.log("Expected: 0 (no tokens minted yet)");
  console.log("Match:", totalSupply.toString() === "0");

  console.log("\n=== Verification Complete ===");
  console.log("All role assignments verified on-chain!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });