const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  console.log("=== Check Wallet Token Balances ===\n");

  const walletAddress = process.env.YOUR_WALLET_ADDRESS || "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";
  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");

  console.log("Wallet Address:", walletAddress);

  const lxonAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const wethAddress = "0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c";

  const erc20ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)"
  ];

  console.log("\n=== Native LXON Balance ===");
  const nativeBalance = await provider.getBalance(walletAddress);
  console.log("Native LXON:", ethers.formatEther(nativeBalance), "LXON");

  console.log("\n=== LXON Token Balance ===");
  const lxon = new ethers.Contract(lxonAddress, erc20ABI, provider);
  const lxonBalance = await lxon.balanceOf(walletAddress);
  const lxonDecimals = await lxon.decimals();
  const lxonSymbol = await lxon.symbol();
  console.log(`${lxonSymbol} Balance:`, ethers.formatUnits(lxonBalance, lxonDecimals));
  console.log("Raw Balance:", lxonBalance.toString());

  console.log("\n=== WETH Token Balance ===");
  const weth = new ethers.Contract(wethAddress, erc20ABI, provider);
  const wethBalance = await weth.balanceOf(walletAddress);
  const wethDecimals = await weth.decimals();
  const wethSymbol = await weth.symbol();
  console.log(`${wethSymbol} Balance:`, ethers.formatUnits(wethBalance, wethDecimals));
  console.log("Raw Balance:", wethBalance.toString());

  console.log("\n=== Summary ===");
  console.log("Native LXON:", ethers.formatEther(nativeBalance));
  console.log("LXON Token:", ethers.formatUnits(lxonBalance, lxonDecimals));
  console.log("WETH Token:", ethers.formatUnits(wethBalance, wethDecimals));

  console.log("\n=== If Tokens Not Showing in MetaMask ===");
  console.log("1. Import LXON Token:");
  console.log("   - Contract: 0xc0177883C0c662870855660495C697385FE040f5");
  console.log("   - Symbol: LXON");
  console.log("   - Decimals: 6");
  console.log("\n2. Import WETH Token:");
  console.log("   - Contract: 0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c");
  console.log("   - Symbol: WETH");
  console.log("   - Decimals: 18");
  console.log("\n3. After importing, tokens will show in MetaMask and swap interface");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
