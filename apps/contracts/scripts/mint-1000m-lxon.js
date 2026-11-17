const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const DEPLOYER_ADDRESS = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
const RECIPIENT = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"; // Your wallet

const LXON_ABI = [
  "function mint(address to, uint256 usdCents, bytes32 depositRef) external",
  "function updateCeiling(uint256 usdCents, bytes32 attestationHash) external",
  "function reserveCeiling() view returns (uint256)",
  "function pendingRedeem() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function grantRole(bytes32 role, address account) external",
  "function paused() view returns (bool)",
  "function MINT_ROLE() view returns (bytes32)",
  "function ORACLE_ROLE() view returns (bytes32)",
  "function GUARDIAN_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)"
];

async function main() {
  console.log("=== Mint 1000M LXON - Step by Step ===\n");

  const deployerKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerKey) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(deployerKey, provider);

  console.log("Deployer:", wallet.address);
  console.log("Recipient:", RECIPIENT);
  console.log();

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);

  // Get roles
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();
  const DEFAULT_ADMIN_ROLE = await lxon.DEFAULT_ADMIN_ROLE();

  // Check if deployer has roles
  const hasMintRole = await lxon.hasRole(MINT_ROLE, wallet.address);
  const hasOracleRole = await lxon.hasRole(ORACLE_ROLE, wallet.address);
  const hasAdminRole = await lxon.hasRole(DEFAULT_ADMIN_ROLE, wallet.address);

  console.log("=== Current Roles ===");
  console.log("Has MINT_ROLE:", hasMintRole);
  console.log("Has ORACLE_ROLE:", hasOracleRole);
  console.log("Has DEFAULT_ADMIN_ROLE:", hasAdminRole);
  console.log();

  // Step 1: Grant ORACLE_ROLE if needed
  if (!hasOracleRole && hasAdminRole) {
    console.log("=== Step 1: Granting ORACLE_ROLE to deployer ===");
    try {
      const tx = await lxon.grantRole(ORACLE_ROLE, wallet.address);
      console.log("Transaction:", tx.hash);
      await tx.wait();
      console.log("✅ ORACLE_ROLE granted");
    } catch (error) {
      console.error("❌ Failed to grant ORACLE_ROLE:", error.message);
      return;
    }
  } else if (hasOracleRole) {
    console.log("✅ Already has ORACLE_ROLE");
  } else {
    console.log("❌ Cannot grant ORACLE_ROLE (no DEFAULT_ADMIN_ROLE)");
    return;
  }

  // Step 2: Set reserve ceiling
  console.log("\n=== Step 2: Setting Reserve Ceiling ===");
  const desiredLXON = 1000000000n; // 1000M
  const usdCentsNeeded = desiredLXON * 100n; // 1 LXON = 1 USD = 100 cents
  console.log("Setting ceiling to:", usdCentsNeeded.toString(), "USD cents");
  console.log("(This allows minting up to 1000M LXON at $1 each)");

  try {
    const attestationHash = ethers.keccak256(ethers.toUtf8Bytes("initial-ceiling"));
    const tx = await lxon.updateCeiling(usdCentsNeeded, attestationHash);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Reserve ceiling set");
  } catch (error) {
    console.error("❌ Failed to set reserve ceiling:", error.message);
    return;
  }

  // Step 3: Grant MINT_ROLE if needed
  const hasMintRoleNow = await lxon.hasRole(MINT_ROLE, wallet.address);
  if (!hasMintRoleNow && hasAdminRole) {
    console.log("\n=== Step 3: Granting MINT_ROLE to deployer ===");
    try {
      const tx = await lxon.grantRole(MINT_ROLE, wallet.address);
      console.log("Transaction:", tx.hash);
      await tx.wait();
      console.log("✅ MINT_ROLE granted");
    } catch (error) {
      console.error("❌ Failed to grant MINT_ROLE:", error.message);
      return;
    }
  } else if (hasMintRoleNow) {
    console.log("✅ Already has MINT_ROLE");
  }

  // Step 4: Mint tokens
  console.log("\n=== Step 4: Minting 1000M LXON ===");
  console.log("Recipient:", RECIPIENT);
  console.log("Amount:", desiredLXON.toString(), "LXON");

  try {
    const depositRef = ethers.keccak256(ethers.toUtf8Bytes("initial-mint"));
    const tx = await lxon.mint(RECIPIENT, usdCentsNeeded, depositRef);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ 1000M LXON minted to", RECIPIENT);
  } catch (error) {
    console.error("❌ Failed to mint:", error.message);
    return;
  }

  // Verify
  console.log("\n=== Verification ===");
  const totalSupply = await lxon.totalSupply();
  const balance = await lxon.balanceOf(RECIPIENT);
  const decimals = await lxon.decimals();

  console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals));
  console.log("Recipient Balance:", ethers.formatUnits(balance, decimals));
  console.log("\n✅ All steps completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
