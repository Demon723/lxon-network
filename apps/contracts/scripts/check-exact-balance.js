const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const SENDER = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)"
];

async function main() {
  console.log("=== Check Exact Balance ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const lxon = new ethers.Contract(LXON_ADDRESS, ERC20_ABI, provider);

  const balance = await lxon.balanceOf(SENDER);
  const totalSupply = await lxon.totalSupply();
  const decimals = await lxon.decimals();

  console.log("Decimals:", decimals);
  console.log("Balance (raw):", balance.toString());
  console.log("Balance (formatted):", ethers.formatUnits(balance, decimals));
  console.log("Total Supply (raw):", totalSupply.toString());
  console.log("Total Supply (formatted):", ethers.formatUnits(totalSupply, decimals));
  console.log();

  const balanceNumber = Number(ethers.formatUnits(balance, decimals));
  if (balanceNumber >= 1000000000) {
    console.log("✅ Confirmed: 1B+ LXON in wallet");
  } else {
    console.log("❌ Balance is less than 1B");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
