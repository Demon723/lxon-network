const { ethers } = require("ethers");
const fs = require("fs");

// Contract addresses
const WETH = "0x4d857b3e030bA985c5D32611Ff69238975790Be7";
const LXON = "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35";
const PAIR = "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519";
const UNIVERSAL_ROUTER = "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a";

// Token ABIs
const LXON_ABI = [
  "function mint(address to, uint256 amount) external",
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function deposit() payable",
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const ROUTER_ABI = [
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)"
];

async function main() {
  console.log("=== Adding Liquidity to DEX Pair ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deployer:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("Native balance:", ethers.formatEther(balance), "LXON\n");

  const lxonToken = new ethers.Contract(LXON, LXON_ABI, wallet);
  const wethToken = new ethers.Contract(WETH, WETH_ABI, wallet);
  const router = new ethers.Contract(UNIVERSAL_ROUTER, ROUTER_ABI, wallet);

  // Mint LXON tokens
  console.log("=== Minting LXON tokens ===");
  const mintAmount = ethers.parseEther("10000");
  try {
    const mintTx = await lxonToken.mint(wallet.address, mintAmount);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ Minted 10,000 LXON");
  } catch (error) {
    console.error("❌ Failed to mint LXON:", error.message);
    console.log("   Try using original LXON token or different approach");
    return;
  }

  // Wrap some LXON to WETH
  console.log("\n=== Wrapping LXON to WETH ===");
  const wrapAmount = ethers.parseEther("5000");
  try {
    const wrapTx = await wethToken.deposit({ value: wrapAmount });
    console.log("Wrap transaction:", wrapTx.hash);
    await wrapTx.wait();
    console.log("✅ Wrapped 5,000 LXON to WETH");
  } catch (error) {
    console.error("❌ Failed to wrap:", error.message);
    return;
  }

  // Check balances
  console.log("\n=== Checking balances ===");
  const lxonBalance = await lxonToken.balanceOf(wallet.address);
  const wethBalance = await wethToken.balanceOf(wallet.address);
  console.log("LXON balance:", ethers.formatEther(lxonBalance));
  console.log("WETH balance:", ethers.formatEther(wethBalance));

  // Approve router
  console.log("\n=== Approving router ===");
  const approveLxon = await lxonToken.approve(UNIVERSAL_ROUTER, ethers.MaxUint256);
  await approveLxon.wait();
  console.log("✅ Approved LXON");

  const approveWeth = await wethToken.approve(UNIVERSAL_ROUTER, ethers.MaxUint256);
  await approveWeth.wait();
  console.log("✅ Approved WETH");

  // Add liquidity
  console.log("\n=== Adding liquidity ===");
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

  try {
    const liquidityTx = await router.addLiquidity(
      LXON,
      WETH,
      ethers.parseEther("5000"), // LXON amount
      ethers.parseEther("5000"), // WETH amount
      ethers.parseEther("4000"), // min LXON
      ethers.parseEther("4000"), // min WETH
      wallet.address,
      deadline
    );
    console.log("Liquidity transaction:", liquidityTx.hash);
    await liquidityTx.wait();
    console.log("✅ Liquidity added");
  } catch (error) {
    console.error("❌ Failed to add liquidity:", error.message);
  }

  console.log("\n=== Liquidity Addition Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
