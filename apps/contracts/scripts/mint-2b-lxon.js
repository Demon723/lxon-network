const { ethers } = require("ethers");
require("dotenv").config");

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const LXON_ABI = [
  "function mint(address to, uint256 usdCents, bytes32 depositRef) external",
  "function reserveCeiling() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function updateCeiling(uint256 usdCents, bytes32 attestationHash) external",
  "function ORACLE_ROLE() view returns (bytes32)",
  "function MINT_ROLE() view returns (bytes32)",
  "function hasRole(bytes32 role, address account) view returns (bool)"
];

async function main() {
  console.log("=== Mint 2B LXON ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);

  // Check current state
  console.log("\n=== Current State ===");
  const totalSupply = await lxon.totalSupply();
  const reserveCeiling = await lxon.reserveCeiling();
  const lxonDecimals = await lxon.decimals();

  console.log("Total Supply:", ethers.formatUnits(totalSupply, lxonDecimals));
  console.log("Reserve Ceiling:", reserveCeiling.toString(), "USD cents ($" + (Number(reserveCeiling) / 100).toFixed(0) + ")");

  // Check roles
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();
  const MINT_ROLE = await lxon.MINT_ROLE();
  const hasOracleRole = await lxon.hasRole(ORACLE_ROLE, wallet.address);
  const hasMintRole = await lxon.hasRole(MINT_ROLE, wallet.address);

  console.log("Has ORACLE_ROLE:", hasOracleRole);
  console.log("Has MINT_ROLE:", hasMintRole);

  // Calculate needed ceiling
  const currentLxonSupply = Number(ethers.formatUnits(totalSupply, lxonDecimals));
  const lxonToMint = 2000000000; // 2B LXON
  const newTotalSupply = currentLxonSupply + lxonToMint;
  const newCeilingCents = newTotalSupply * 100; // 1 LXON = 1 USD = 100 cents

  console.log("\n=== Calculation ===");
  console.log("Current supply:", currentLxonSupply);
  console.log("LXON to mint:", lxonToMint);
  console.log("New total supply:", newTotalSupply);
  console.log("New ceiling needed:", newCeilingCents, "USD cents ($" + (newCeilingCents / 100).toFixed(0) + ")");

  // Step 1: Update ceiling
  console.log("\n=== Step 1: Update Reserve Ceiling ===");
  const attestationHash = ethers.keccak256(ethers.toUtf8Bytes("increase-ceiling-2b"));

  try {
    const updateTx = await lxon.updateCeiling(newCeilingCents, attestationHash);
    console.log("Update ceiling transaction:", updateTx.hash);
    await updateTx.wait();
    console.log("✅ Reserve ceiling updated");
  } catch (error) {
    console.error("❌ Failed to update ceiling:", error.message);
    return;
  }

  // Verify
  const newCeiling = await lxon.reserveCeiling();
  console.log("New reserve ceiling:", newCeiling.toString(), "USD cents ($" + (Number(newCeiling) / 100).toFixed(0) + ")");

  // Step 2: Mint 2B LXON
  console.log("\n=== Step 2: Mint 2B LXON ===");
  const targetAddress = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"; // 1B address
  const usdCents = lxonToMint * 100n; // 2B LXON = 2B USD = 200B cents
  const depositRef = ethers.keccak256(ethers.toUtf8Bytes("mint-2b-lxon"));

  console.log("Minting to:", targetAddress);
  console.log("Amount:", lxonToMint, "LXON");
  console.log("USD cents:", usdCents.toString());

  try {
    const mintTx = await lxon.mint(targetAddress, usdCents, depositRef);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ 2B LXON minted successfully");
  } catch (error) {
    console.error("❌ Failed to mint:", error.message);
    return;
  }

  // Verify
  console.log("\n=== Verification ===");
  const finalTotalSupply = await lxon.totalSupply();
  const finalBalance = await lxon.balanceOf(targetAddress);

  console.log("Final total supply:", ethers.formatUnits(finalTotalSupply, lxonDecimals));
  console.log("Target address balance:", ethers.formatUnits(finalBalance, lxonDecimals));

  console.log("\n✅ 2B LXON minted successfully!");
  console.log("Total supply is now:", ethers.formatUnits(finalTotalSupply, lxonDecimals));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
