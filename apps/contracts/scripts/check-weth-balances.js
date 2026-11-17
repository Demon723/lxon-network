const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const YOUR_WALLET = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";
const FOUNDER_WALLET = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";
const DEPLOYER_WALLET = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  console.log("=== WETH Balance Check Across Wallets ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const weth = new ethers.Contract(WETH_ADDRESS, ERC20_ABI, provider);

  const decimals = await weth.decimals();
  const symbol = await weth.symbol();

  console.log(`Token: ${symbol} (${decimals} decimals)\n`);

  const wallets = [
    { name: "Your Wallet", address: YOUR_WALLET },
    { name: "Founder Wallet", address: FOUNDER_WALLET },
    { name: "Deployer Wallet", address: DEPLOYER_WALLET }
  ];

  let totalBalance = 0n;

  for (const wallet of wallets) {
    const balance = await weth.balanceOf(wallet.address);
    const formatted = Number(ethers.formatUnits(balance, decimals));
    totalBalance += balance;

    console.log(`${wallet.name}:`);
    console.log(`  Address: ${wallet.address}`);
    console.log(`  Balance: ${formatted.toFixed(4)} ${symbol}`);
    if (formatted > 0) {
      console.log(`  Value: ~$${(formatted * 1.5).toFixed(2)} USD (assuming $1.50/LXON)`);
    }
    console.log();
  }

  const totalFormatted = Number(ethers.formatUnits(totalBalance, decimals));
  console.log(`Total WETH across all wallets: ${totalFormatted.toFixed(4)} ${symbol}`);
  console.log(`Total Value: ~$${(totalFormatted * 1.5).toFixed(2)} USD`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
