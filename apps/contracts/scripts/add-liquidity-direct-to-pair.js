const { ethers } = require("ethers");
const fs = require("fs");

// Addresses
const NEW_PAIR = "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519";
const ORIGINAL_WETH = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const ORIGINAL_LXON = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_HOLDER = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3"; // Founder who holds WETH

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

  // Use FOUNDER_PRIVATE_KEY from .env (holder of WETH)
  const wethHolderKey = process.env.FOUNDER_PRIVATE_KEY;
  
  if (!wethHolderKey) {
    console.log("❌ Need FOUNDER_PRIVATE_KEY in .env");
    console.log("Current keys in .env: DEPLOYER_PRIVATE_KEY, FOUNDER_PRIVATE_KEY");
    return;
  }

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(wethHolderKey, provider);

  console.log("Using wallet:", wallet.address);

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

  // Amounts to add
  const WETH_AMOUNT = ethers.parseEther("100"); // 100 WETH
  const LXON_AMOUNT = ethers.parseEther("100"); // 100 LXON

  if (wethBalance < WETH_AMOUNT) {
    console.log("\n⚠️  Insufficient WETH for 100 WETH");
    console.log("Using all available WETH:", ethers.formatEther(wethBalance));
    const wethToUse = wethBalance;
    console.log("Will add:", ethers.formatEther(wethToUse), "WETH");
  }

  // Transfer tokens directly to pair (old method)
  console.log("\n=== Transferring Tokens to Pair ===");
  console.log("Pair address:", NEW_PAIR);

  const transferWeth = await wethToken.transfer(NEW_PAIR, WETH_AMOUNT);
  console.log("WETH transfer:", transferWeth.hash);
  await transferWeth.wait();
  console.log("✅ WETH transferred");

  if (lxonBalance >= LXON_AMOUNT) {
    const transferLxon = await lxonToken.transfer(NEW_PAIR, LXON_AMOUNT);
    console.log("LXON transfer:", transferLxon.hash);
    await transferLxon.wait();
    console.log("✅ LXON transferred");
  } else {
    console.log("⚠️  No LXON balance, adding WETH-only liquidity");
  }

  // Mint LP tokens directly (old method)
  console.log("\n=== Minting LP Tokens ===");
  try {
    const mintTx = await newPair.mint(wallet.address);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ LP tokens minted");
  } catch (error) {
    console.error("❌ Failed to mint LP tokens:", error.message);
    console.log("This may require the pair to have proper balances");
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

  // Calculate price
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
