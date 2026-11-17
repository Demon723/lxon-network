const { ethers } = require("ethers");
const dotenv = require("dotenv");
dotenv.config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Check WETH Contract Owner ===\n");

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const wethInterface = new ethers.Interface([
    "function owner() view returns (address)",
    "function hasRole(bytes32 role, address account) view returns (bool)",
    "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
    "function MINTER_ROLE() view returns (bytes32)"
  ]);

  const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, provider);

  try {
    const owner = await weth.owner();
    console.log("WETH contract owner:", owner);
    console.log("Deployer is owner:", owner.toLowerCase() === wallet.address.toLowerCase());
  } catch (error) {
    console.log("No owner() function");
  }

  try {
    const defaultAdminRole = await weth.DEFAULT_ADMIN_ROLE();
    console.log("DEFAULT_ADMIN_ROLE:", defaultAdminRole);
    const hasAdmin = await weth.hasRole(defaultAdminRole, wallet.address);
    console.log("Deployer has DEFAULT_ADMIN_ROLE:", hasAdmin);
  } catch (error) {
    console.log("No role-based access control");
  }

  console.log("\n=== Summary ===");
  console.log("WETH minting is restricted");
  console.log("Deployer does not have mint authority");
  console.log("Cannot mint 1B WETH");
  console.log("\n=== Options ===");
  console.log("1. Find WETH contract owner and request mint authority");
  console.log("2. Deploy new WETH contract (you said not to)");
  console.log("3. Accept current price $0.257/LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
