const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const YOUR_WALLET = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  console.log("=== Verify 1000M LXON Mint ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const lxon = new ethers.Contract(LXON_ADDRESS, ERC20_ABI, provider);

  const totalSupply = await lxon.totalSupply();
  const balance = await lxon.balanceOf(YOUR_WALLET);
  const decimals = await lxon.decimals();
  const symbol = await lxon.symbol();

  console.log("Token:", symbol);
  console.log("Decimals:", decimals);
  console.log();
  console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals));
  console.log("Your Balance:", ethers.formatUnits(balance, decimals));
  console.log("Wallet:", YOUR_WALLET);
  console.log();

  const balanceNumber = Number(ethers.formatUnits(balance, decimals));
  if (balanceNumber >= 1000000000) {
    console.log("✅ SUCCESS: You have 1,000,000,000+ LXON!");
    console.log("Value at $1.50/LXON: $" + (balanceNumber * 1.5).toLocaleString());
  } else {
    console.log("❌ Balance is less than 1000M");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
