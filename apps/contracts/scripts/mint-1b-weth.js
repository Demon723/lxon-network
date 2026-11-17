const { ethers } = require("ethers");
require("dotenv").config");

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Try to Mint 1B WETH ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const wethInterface = new ethers.Interface([
    "function mint(address to, uint256 amount) external",
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)"
  ]);

  const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, wallet);

  const amountToMint = ethers.parseEther("1000000000"); // 1B WETH

  console.log("Attempting to mint 1B WETH to:", wallet.address);

  try {
    const tx = await weth.mint(wallet.address, amountToMint);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Successfully minted 1B WETH!");

    const balance = await weth.balanceOf(wallet.address);
    const decimals = await weth.decimals();
    console.log("New WETH balance:", ethers.formatUnits(balance, decimals));
  } catch (error) {
    console.log("❌ Mint failed:", error.message);
    console.log("\n=== Check if Deployer is Owner ===");
    
    // Try to check who owns the contract
    try {
      const ownerInterface = new ethers.Interface(["function owner() view returns (address)"]);
      const ownerContract = new ethers.Contract(WETH_ADDRESS, ownerInterface, provider);
      const owner = await ownerContract.owner();
      console.log("WETH contract owner:", owner);
      console.log("Deployer is owner:", owner.toLowerCase() === wallet.address.toLowerCase());
    } catch (e) {
      console.log("No owner() function or failed to check");
    }

    console.log("\n=== Conclusion ===");
    console.log("WETH minting is restricted");
    console.log("Deployer does not have mint authority");
    console.log("Cannot mint 1B WETH");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
