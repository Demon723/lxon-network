const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const SENDER = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";
const DEPLOYER = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

const LXON_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function MINT_ROLE() view returns (bytes32)",
  "function ORACLE_ROLE() view returns (bytes32)",
  "function GUARDIAN_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)"
];

async function main() {
  console.log("=== Check if Sender Has Special Roles ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, provider);

  const balance = await lxon.balanceOf(SENDER);
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();
  const GUARDIAN_ROLE = await lxon.GUARDIAN_ROLE();
  const DEFAULT_ADMIN_ROLE = await lxon.DEFAULT_ADMIN_ROLE();

  const hasMint = await lxon.hasRole(MINT_ROLE, SENDER);
  const hasOracle = await lxon.hasRole(ORACLE_ROLE, SENDER);
  const hasGuardian = await lxon.hasRole(GUARDIAN_ROLE, SENDER);
  const hasAdmin = await lxon.hasRole(DEFAULT_ADMIN_ROLE, SENDER);

  console.log("Sender:", SENDER);
  console.log("Balance:", ethers.formatEther(balance), "LXON");
  console.log();
  console.log("Has MINT_ROLE:", hasMint);
  console.log("Has ORACLE_ROLE:", hasOracle);
  console.log("Has GUARDIAN_ROLE:", hasGuardian);
  console.log("Has DEFAULT_ADMIN_ROLE:", hasAdmin);
  console.log();

  if (!hasMint && !hasOracle && !hasGuardian && !hasAdmin) {
    console.log("❌ Sender has no special roles.");
    console.log("❌ Cannot transfer without private key.");
    console.log();
    console.log("The 1 billion LXON are stuck in this address.");
    console.log("Without the private key, they cannot be moved.");
  } else {
    console.log("✅ Sender has special roles.");
    console.log("This might allow some operations, but not standard transfers.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
