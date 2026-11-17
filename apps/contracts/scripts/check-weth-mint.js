const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Check WETH Contract for Mint Function ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  // Try to call a potential mint function
  const wethInterface = new ethers.Interface([
    "function mint(address to, uint256 amount) external",
    "function MINTER_ROLE() view returns (bytes32)",
    "function hasRole(bytes32 role, address account) view returns (bool)"
  ]);

  const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, provider);

  try {
    console.log("Checking for MINTER_ROLE...");
    const minterRole = await weth.MINTER_ROLE();
    console.log("MINTER_ROLE:", minterRole);

    const hasMinterRole = await weth.hasRole(minterRole, wallet.address);
    console.log("Deployer has MINTER_ROLE:", hasMinterRole);

    if (hasMinterRole) {
      console.log("\n✅ Deployer can mint WETH directly!");
      console.log("Would you like to mint 111.6M WETH?");
    } else {
      console.log("\n❌ Deployer does not have MINTER_ROLE");
      console.log("Cannot mint WETH directly");
    }
  } catch (error) {
    console.log("Contract does not have role-based minting");
    console.log("Standard WETH9 only allows deposit/withdraw");
  }

  // Check if there's a custom mint function
  try {
    console.log("\nChecking for custom mint function...");
    const code = await provider.getCode(WETH_ADDRESS);
    console.log("Contract size:", code.length, "bytes");
    console.log("Standard WETH9 is ~400 bytes");
    
    if (code.length > 1000) {
      console.log("Contract is larger than standard WETH9");
      console.log("May have additional functions");
    }
  } catch (error) {
    console.error("Error checking contract:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
