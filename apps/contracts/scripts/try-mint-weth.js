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

  // Try different mint function signatures
  const wethInterface = new ethers.Interface([
    "function mint(address to, uint256 amount) external",
    "function mint(uint256 amount) external",
    "function mint(address to) external payable",
    "function mint() external payable"
  ]);

  const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, wallet);

  const amountToMint = ethers.parseEther("111600000"); // 111.6M WETH

  console.log("Attempting to mint 111.6M WETH...");

  try {
    // Try mint(address to, uint256 amount)
    console.log("\nTrying mint(address to, uint256 amount)...");
    const tx = await weth.mint(wallet.address, amountToMint);
    console.log("Transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Successfully minted WETH!");
  } catch (error) {
    console.log("❌ mint(address to, uint256 amount) failed:", error.message.substring(0, 100));

    try {
      // Try mint(uint256 amount)
      console.log("\nTrying mint(uint256 amount)...");
      const tx = await weth.mint(amountToMint);
      console.log("Transaction:", tx.hash);
      await tx.wait();
      console.log("✅ Successfully minted WETH!");
    } catch (error2) {
      console.log("❌ mint(uint256 amount) failed:", error2.message.substring(0, 100));

      try {
        // Try mint(address to) payable
        console.log("\nTrying mint(address to) payable...");
        const tx = await weth.mint(wallet.address, { value: ethers.parseEther("1") });
        console.log("Transaction:", tx.hash);
        await tx.wait();
        console.log("✅ Successfully minted WETH!");
      } catch (error3) {
        console.log("❌ mint(address to) payable failed:", error3.message.substring(0, 100));

        console.log("\n❌ WETH contract does not have a mint function");
        console.log("Only standard deposit/withdraw available");
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
