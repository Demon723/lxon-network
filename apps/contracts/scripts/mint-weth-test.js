const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Try Minting WETH Directly ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const wethInterface = new ethers.Interface([
    "function mint(address to, uint256 amount) external",
    "function mint(uint256 amount) external"
  ]);

  const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, wallet);

  const amountToMint = ethers.parseEther("111600000");

  console.log("Attempting to mint 111.6M WETH...");

  try {
    const tx = await weth.mint(wallet.address, amountToMint);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Successfully minted WETH!");
  } catch (error) {
    console.log("❌ Mint failed:", error.message.substring(0, 100));
    console.log("\nWETH contract does not have a mint function");
    console.log("Only standard deposit/withdraw available");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
