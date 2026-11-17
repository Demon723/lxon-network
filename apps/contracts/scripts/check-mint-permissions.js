const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const DEPLOYER_ADDRESS = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

const LXON_ABI = [
  "function mint(address to, uint256 usdCents, bytes32 depositRef) external",
  "function reserveCeiling() view returns (uint256)",
  "function pendingRedeem() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function getRoleAdmin(bytes32 role) view returns (bytes32)",
  "function grantRole(bytes32 role, address account) external",
  "function paused() view returns (bool)",
  "function MINT_ROLE() view returns (bytes32)",
  "function ORACLE_ROLE() view returns (bytes32)",
  "function GUARDIAN_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)"
];

async function main() {
  console.log("=== LXON Minting Check ===\n");

  const deployerKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerKey) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(deployerKey, provider);

  console.log("Deployer:", wallet.address);
  console.log("Expected:", DEPLOYER_ADDRESS);

  if (wallet.address.toLowerCase() !== DEPLOYER_ADDRESS.toLowerCase()) {
    console.log("⚠️  Wallet address doesn't match DEPLOYER_ADDRESS");
  }

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);

  // Check current state
  console.log("\n=== Current State ===");
  const reserveCeiling = await lxon.reserveCeiling();
  const pendingRedeem = await lxon.pendingRedeem();
  const totalSupply = await lxon.totalSupply();
  const decimals = await lxon.decimals();
  const paused = await lxon.paused();

  console.log("Reserve Ceiling:", Number(reserveCeiling).toLocaleString(), "USD cents");
  console.log("Pending Redeem:", Number(pendingRedeem).toLocaleString(), "USD cents");
  console.log("Total Supply:", Number(ethers.formatUnits(totalSupply, decimals)).toLocaleString(), "LXON");
  console.log("Paused:", paused);
  console.log("Decimals:", decimals);

  // Check roles
  console.log("\n=== Role Check ===");
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();
  const GUARDIAN_ROLE = await lxon.GUARDIAN_ROLE();
  const DEFAULT_ADMIN_ROLE = await lxon.DEFAULT_ADMIN_ROLE();

  const hasMintRole = await lxon.hasRole(MINT_ROLE, wallet.address);
  const hasAdminRole = await lxon.hasRole(DEFAULT_ADMIN_ROLE, wallet.address);
  const hasOracleRole = await lxon.hasRole(ORACLE_ROLE, wallet.address);
  const hasGuardianRole = await lxon.hasRole(GUARDIAN_ROLE, wallet.address);

  console.log("Has MINT_ROLE:", hasMintRole);
  console.log("Has DEFAULT_ADMIN_ROLE:", hasAdminRole);
  console.log("Has ORACLE_ROLE:", hasOracleRole);
  console.log("Has GUARDIAN_ROLE:", hasGuardianRole);

  // Calculate what's needed for 1000M LXON
  console.log("\n=== Minting 1000M LXON ===");
  const desiredLXON = 1000000000n; // 1000M
  const usdCentsNeeded = desiredLXON * 100n; // 1 LXON = 1 USD = 100 cents
  const maxSupply = (reserveCeiling - pendingRedeem) * 10000n; // contract uses 1e4 multiplier

  console.log("Desired LXON:", desiredLXON.toString());
  console.log("USD cents needed:", usdCentsNeeded.toString());
  console.log("Current reserve ceiling (USD cents):", reserveCeiling.toString());
  console.log("Max supply allowed:", maxSupply.toString(), "LXON units");
  console.log("Current total supply:", totalSupply.toString());

  if (reserveCeiling === 0n) {
    console.log("\n❌ Reserve ceiling is 0. Cannot mint.");
    console.log("Need to:");
    console.log("1. Set reserve ceiling via updateCeiling()");
    console.log("2. Requires ORACLE_ROLE or DEFAULT_ADMIN_ROLE");
  }

  if (!hasMintRole && !hasAdminRole) {
    console.log("\n❌ No MINT_ROLE or DEFAULT_ADMIN_ROLE. Cannot mint.");
    console.log("Need to grant MINT_ROLE first.");
  }

  if (paused) {
    console.log("\n❌ Contract is paused. Cannot mint.");
    console.log("Need to unpause first (requires MINT_ROLE or GUARDIAN_ROLE).");
  }

  // Show what's possible
  console.log("\n=== What Can Be Minted ===");
  const maxMintable = maxSupply - totalSupply;
  const maxMintableLXON = ethers.formatUnits(maxMintable, decimals);
  console.log("Max mintable LXON:", maxMintableLXON);

  if (maxMintable >= desiredLXON && (hasMintRole || hasAdminRole) && !paused) {
    console.log("\n✅ Can mint 1000M LXON");
    console.log("Would need:", usdCentsNeeded.toString(), "USD cents as deposit reference");
  } else {
    console.log("\n❌ Cannot mint 1000M LXON with current configuration");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
