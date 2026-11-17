const { ethers } = require("ethers");
const fs = require("fs");

// Use original deployed contracts which have balances
const WETH_ORIGINAL = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const LXON_ORIGINAL = "0xc0177883C0c662870855660495C697385FE040f5";
const NEW_PAIR = "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519";
const UNIVERSAL_ROUTER = "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a";

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function decimals() view returns (uint8)"
];

const ROUTER_ABI = [
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)"
];

async function main() {
  console.log("=== Adding Liquidity using Original Tokens ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deployer:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("Native balance:", ethers.formatEther(balance), "LXON\n");

  const wethToken = new ethers.Contract(WETH_ORIGINAL, ERC20_ABI, wallet);
  const lxonToken = new ethers.Contract(LXON_ORIGINAL, ERC20_ABI, wallet);
  const router = new ethers.Contract(UNIVERSAL_ROUTER, ROUTER_ABI, wallet);

  // Check balances
  console.log("=== Checking original token balances ===");
  const wethBalance = await wethToken.balanceOf(wallet.address);
  const lxonBalance = await lxonToken.balanceOf(wallet.address);
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatEther(lxonBalance));

  if (wethBalance === 0n) {
    console.log("\n❌ No WETH balance in deployer wallet");
    console.log("Need to transfer WETH from the address that has it");
    console.log("WETH is at: 0x86a7da576852126c8421F7a25F8dE7cEDF9553C4");
    return;
  }

  // Approve router
  console.log("\n=== Approving router ===");
  const approveWeth = await wethToken.approve(UNIVERSAL_ROUTER, ethers.MaxUint256);
  await approveWeth.wait();
  console.log("✅ Approved WETH");

  if (lxonBalance > 0n) {
    const approveLxon = await lxonToken.approve(UNIVERSAL_ROUTER, ethers.MaxUint256);
    await approveLxon.wait();
    console.log("✅ Approved LXON");
  }

  // Add liquidity with WETH only (will create single-sided liquidity or fail)
  console.log("\n=== Adding liquidity ===");
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  try {
    const liquidityTx = await router.addLiquidity(
      LXON_ORIGINAL,
      WETH_ORIGINAL,
      lxonBalance > 0n ? lxonBalance : ethers.parseEther("0"),
      wethBalance,
      lxonBalance > 0n ? ethers.parseEther(String(Number(lxonBalance) * 0.9)) : ethers.parseEther("0"),
      ethers.parseEther(String(Number(wethBalance) * 0.9)),
      wallet.address,
      deadline
    );
    console.log("Liquidity transaction:", liquidityTx.hash);
    await liquidityTx.wait();
    console.log("✅ Liquidity added");
  } catch (error) {
    console.error("❌ Failed to add liquidity:", error.message);
    console.log("\nNote: Need both token balances for liquidity");
    console.log("Consider using the original DEX which already has liquidity");
  }

  console.log("\n=== Status ===");
  console.log("New DEX pair created at:", NEW_PAIR);
  console.log("But liquidity not added due to missing token balances");
  console.log("Original DEX still works with existing liquidity");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
