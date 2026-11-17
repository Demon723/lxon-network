const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

async function main() {
  console.log("=== Try All Possible Mint Signatures ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const amountToMint = ethers.parseEther("111600000");

  // Try all possible mint function signatures
  const signatures = [
    "function mint(address to, uint256 amount) external",
    "function mint(uint256 amount) external",
    "function mint(address to) external",
    "function mint() external",
    "function _mint(address to, uint256 amount) external",
    "function _mint(uint256 amount) external"
  ];

  for (const sig of signatures) {
    try {
      console.log(`\nTrying: ${sig}`);
      const wethInterface = new ethers.Interface([sig]);
      const weth = new ethers.Contract(WETH_ADDRESS, wethInterface, wallet);

      const methodName = sig.split("(")[0].split(" ")[1];
      const args = methodName === "mint" && sig.includes("address to, uint256 amount") 
        ? [wallet.address, amountToMint]
        : methodName === "mint" && sig.includes("uint256 amount")
        ? [amountToMint]
        : methodName === "mint" && sig.includes("address to")
        ? [wallet.address]
        : [];

      const tx = await weth[methodName](...args);
      console.log("✅ Transaction:", tx.hash);
      await tx.wait();
      console.log("✅ Successfully minted WETH!");
      return;
    } catch (error) {
      console.log("❌ Failed:", error.message.substring(0, 80));
    }
  }

  console.log("\n❌ All mint attempts failed");
  console.log("WETH contract mint function is restricted");
  console.log("Only authorized addresses can mint");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
