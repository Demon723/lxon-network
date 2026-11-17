const { ethers } = require("ethers");
require("dotenv").config();

// All WETH and LXON addresses we've seen
const ALL_WETH_ADDRESSES = [
  "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4", // Original
  "0x4d857b3e030bA985c5D32611Ff69238975790Be7", // New
  "0x007696cdF0Bf860823126D72C8e3D52448B5285E", // Alternate from old artifacts
];

const ALL_LXON_ADDRESSES = [
  "0xc0177883C0c662870855660495C697385FE040f5", // Original
  "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35", // New
  "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c", // Alternate from old artifacts
  "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707", // Testnet from faucet
];

const ALL_WALLETS = [
  "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b", // Your wallet
  "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3", // Founder
  "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27", // Deployer
  "0x098Ae030804120Def93880a303788d24dc600d00", // Earlier owner
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)"
];

async function main() {
  console.log("=== Comprehensive Token Search - All Contracts and Wallets ===\n");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  console.log(`RPC: ${rpcUrl}`);
  console.log(`Chain ID: ${await provider.getNetwork().then(n => n.chainId)}`);
  console.log();

  // Check all WETH contracts
  console.log("=== Checking All WETH Contracts ===");
  for (const wethAddr of ALL_WETH_ADDRESSES) {
    try {
      const weth = new ethers.Contract(wethAddr, ERC20_ABI, provider);
      const name = await weth.name();
      const symbol = await weth.symbol();
      const decimals = await weth.decimals();
      const totalSupply = await weth.totalSupply();

      console.log(`\n${wethAddr}`);
      console.log(`  Name: ${name}`);
      console.log(`  Symbol: ${symbol}`);
      console.log(`  Decimals: ${decimals}`);
      console.log(`  Total Supply: ${Number(ethers.formatUnits(totalSupply, decimals)).toFixed(4)}`);

      // Check all wallets
      let hasBalance = false;
      for (const wallet of ALL_WALLETS) {
        const balance = await weth.balanceOf(wallet);
        if (balance > 0n) {
          hasBalance = true;
          console.log(`  ✅ ${wallet}: ${Number(ethers.formatUnits(balance, decimals)).toFixed(4)}`);
        }
      }
      if (!hasBalance) {
        console.log(`  ❌ No balance in any known wallet`);
      }
    } catch (error) {
      console.log(`\n${wethAddr}`);
      console.log(`  ❌ Error: ${error.message}`);
    }
  }

  console.log("\n" + "=".repeat(60) + "\n");

  // Check all LXON contracts
  console.log("=== Checking All LXON Contracts ===");
  for (const lxonAddr of ALL_LXON_ADDRESSES) {
    try {
      const lxon = new ethers.Contract(lxonAddr, ERC20_ABI, provider);
      const name = await lxon.name();
      const symbol = await lxon.symbol();
      const decimals = await lxon.decimals();
      const totalSupply = await lxon.totalSupply();

      console.log(`\n${lxonAddr}`);
      console.log(`  Name: ${name}`);
      console.log(`  Symbol: ${symbol}`);
      console.log(`  Decimals: ${decimals}`);
      console.log(`  Total Supply: ${Number(ethers.formatUnits(totalSupply, decimals)).toFixed(4)}`);

      // Check all wallets
      let hasBalance = false;
      for (const wallet of ALL_WALLETS) {
        const balance = await lxon.balanceOf(wallet);
        if (balance > 0n) {
          hasBalance = true;
          console.log(`  ✅ ${wallet}: ${Number(ethers.formatUnits(balance, decimals)).toFixed(4)}`);
        }
      }
      if (!hasBalance) {
        console.log(`  ❌ No balance in any known wallet`);
      }
    } catch (error) {
      console.log(`\n${lxonAddr}`);
      console.log(`  ❌ Error: ${error.message}`);
    }
  }

  console.log("\n" + "=".repeat(60) + "\n");

  // Check native balances
  console.log("=== Checking Native LXON Balances ===");
  for (const wallet of ALL_WALLETS) {
    const balance = await provider.getBalance(wallet);
    const formatted = Number(ethers.formatEther(balance));
    console.log(`${wallet}: ${formatted.toFixed(4)} native LXON`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
