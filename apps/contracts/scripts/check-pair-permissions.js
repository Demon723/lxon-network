const { ethers } = require("ethers");
require("dotenv").config");

const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Check Pair Contract Permissions ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const pairInterface = new ethers.Interface([
    "function factory() view returns (address)",
    "function token0() view returns (address)",
    "function token1() view returns (address)",
    "function owner() view returns (address)",
    "function hasRole(bytes32 role, address account) view returns (bool)",
    "function DEFAULT_ADMIN_ROLE() view returns (bytes32)"
  ]);

  const pair = new ethers.Contract(PAIR_ADDRESS, pairInterface, provider);

  try {
    const factory = await pair.factory();
    console.log("Factory:", factory);
  } catch (error) {
    console.log("No factory()");
  }

  try {
    const owner = await pair.owner();
    console.log("Owner:", owner);
    console.log("Deployer is owner:", owner.toLowerCase() === wallet.address.toLowerCase());
  } catch (error) {
    console.log("No owner()");
  }

  try {
    const adminRole = await pair.DEFAULT_ADMIN_ROLE();
    console.log("DEFAULT_ADMIN_ROLE:", adminRole);
    const hasAdminRole = await pair.hasRole(adminRole, wallet.address);
    console.log("Deployer has DEFAULT_ADMIN_ROLE:", hasAdminRole);
  } catch (error) {
    console.log("No role-based access control");
  }

  const code = await provider.getCode(PAIR_ADDRESS);
  console.log("\nContract size:", code.length, "bytes");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
