const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const WETH_ABI = [
  "function deposit() external payable",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)"
];

async function main() {
  console.log("=== Wrap All Native LXON into WETH ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Wallet:", wallet.address);

  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, wallet);

  // Check native balance
  const nativeBalance = await provider.getBalance(wallet.address);
  console.log("Native LXON balance:", ethers.formatEther(nativeBalance));

  // Keep 100 for gas
  const gasReserve = ethers.parseEther("100");
  const wrapAmount = nativeBalance > gasReserve ? nativeBalance - gasReserve : 0n;

  if (wrapAmount === 0n) {
    console.log("No native LXON to wrap");
    return;
  }

  console.log("Wrapping:", ethers.formatEther(wrapAmount), "native LXON");
  console.log("Keeping:", ethers.formatEther(gasReserve), "for gas");

  try {
    const tx = await weth.deposit({ value: wrapAmount });
    console.log("Wrap transaction:", tx.hash);
    await tx.wait();
    console.log("✅ Wrapped successfully");

    const wethBalance = await weth.balanceOf(wallet.address);
    const wethDecimals = await weth.decimals();
    console.log("New WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));
  } catch (error) {
    console.error("❌ Wrap failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
