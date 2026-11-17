const { ethers } = require("ethers");
const fs = require("fs");
require("dotenv").config();

// Addresses
const NEW_PAIR = "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519";
const ORIGINAL_WETH = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const ORIGINAL_LXON = "0xc0177883C0c662870855660495C697385FE040f5";
const YOUR_WALLET = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"; // Has the WETH

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function decimals() view returns (uint8)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function mint(address to) external returns (uint256 liquidity)",
  "function balanceOf(address) view returns (uint256)"
];

async function main() {
  console.log("=== Adding Liquidity Direct to NEW DEX Pair ===\n");

  // Need YOUR_WALLET private key - not in .env
  const yourWalletKey = process.env.YOUR_WALLET_PRIVATE_KEY;
  
  if (!yourWalletKey) {
    console.log("❌ Need YOUR_WALLET_PRIVATE_KEY in .env");
    console.log("The wallet with WETH is:", YOUR_WALLET);
    console.log("Add YOUR_WALLET_PRIVATE_KEY to .env");
    return;
  }

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(yourWalletKey, provider);

  console.log("Using wallet:", wallet.address);
  console.log("Expected:", YOUR_WALLET);

  if (wallet.address.toLowerCase() !== YOUR_WALLET.toLowerCase()) {
    console.log("⚠️  Wallet address doesn't match YOUR_WALLET");
  }

  const wethToken = new ethers.Contract(ORIGINAL_WETH, ERC20_ABI, wallet);
  const lxonToken = new ethers.Contract(ORIGINAL_LXON, ERC20_ABI, wallet);
  const newPair = new ethers.Contract(NEW_PAIR, PAIR_ABI, wallet);

  // Check balances
  console.log("\n=== Checking Balances ===");
  const wethBalance = await wethToken.balanceOf(wallet.address);
  const lxonBalance = await lxonToken.balanceOf(wallet.address);
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatEther(lxonBalance));

  if (wethBalance === 0n) {
    console.log("\n❌ No WETH balance");
    return;
  }

  console.log("✅ Has WETH balance:", ethers.formatEther(wethBalance));

  // Amounts to add
  const WETH_AMOUNT = ethers.parseEther("100"); // 100 WETH
  const LXON_AMOUNT = ethers.parseEther("100"); // 100 LXON

  if (wethBalance < WETH_AMOUNT) {
    console.log("\n⚠️  Insufficient WETH for 100 WETH");
    console.log("Using 50 WETH instead");
    const wethToUse = ethers.parseEther("50");
    console.log("Will add:", ethers.formatEther(wethToUse), "WETH");
  }

  // Transfer tokens directly to pair
  console.log("\n=== Transferring Tokens to Pair ===");
  console.log("Pair address:", NEW_PAIR);

  const transferWeth = await wethToken.transfer(NEW_PAIR, ethers.parseEther("50"));
  console.log("WETH transfer:", transferWeth.hash);
  await transferWeth.wait();
  console.log("✅ 50 WETH transferred");

  if (lxonBalance >= LXON_AMOUNT) {
    const transferLxon = await lxonToken.transfer(NEW_PAIR, LXON_AMOUNT);
    console.log("LXON transfer:", transferLxon.hash);
    await transferLxon.wait();
    console.log("✅ 100 LXON transferred");
  } else {
    console.log("⚠️  No LXON balance, adding WETH-only liquidity");
  }

  // Mint LP tokens
  console.log("\n=== Minting LP Tokens ===");
  try {
    const mintTx = await newPair.mint(wallet.address);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ LP tokens minted");
  } catch (error) {
    console.error("❌ Failed to mint LP tokens:", error.message);
  }

  // Verify final state
  console.log("\n=== Final State ===");
  const finalWethBalance = await wethToken.balanceOf(NEW_PAIR);
  const finalLxonBalance = await lxonToken.balanceOf(NEW_PAIR);
  const [reserve0, reserve1] = await newPair.getReserves();
  const lpBalance = await newPair.balanceOf(wallet.address);

  console.log("Pair WETH balance:", ethers.formatEther(finalWethBalance));
  console.log("Pair LXON balance:", ethers.formatEther(finalLxonBalance));
  console.log("Reserve0:", ethers.formatEther(reserve0));
  console.log("Reserve1:", ethers.formatEther(reserve1));
  console.log("LP tokens:", ethers.formatEther(lpBalance));

  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatEther(reserve1));
  if (lxonReserve > 0) {
    const price = wethReserve / lxonReserve;
    console.log("Price:", price, "WETH per LXON");
  }

  console.log("\n✅ Liquidity addition complete");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
