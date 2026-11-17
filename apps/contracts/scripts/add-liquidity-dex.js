const { ethers } = require("ethers");
require("dotenv").config();

const LXON_ADDRESS = "0xc0177883C0c662870855660495C697385FE040f5";
const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const PAIR_ADDRESS = "0x3aD52bD5996f16C902225b0d9C111fafE6B77786";
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const LXON_1B_PRIVATE_KEY = process.env.LXON_1B_PRIVATE_KEY;
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const LXON_ABI = [
  "function mint(address to, uint256 usdCents, bytes32 depositRef) external",
  "function reserveCeiling() view returns (uint256)",
  "function pendingRedeem() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const PAIR_ABI = [
  "function mint(address to) external returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function decimals() view returns (uint8)"
];

async function main() {
  console.log("=== Add Liquidity to DEX ===\n");

  if (!DEPLOYER_PRIVATE_KEY) {
    console.log("❌ Need DEPLOYER_PRIVATE_KEY in .env");
    return;
  }

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deployer:", wallet.address);

  const lxon = new ethers.Contract(LXON_ADDRESS, LXON_ABI, wallet);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, wallet);
  const pair = new ethers.Contract(PAIR_ADDRESS, PAIR_ABI, wallet);

  // Check balances
  console.log("\n=== Current Balances ===");
  const wethBalance = await weth.balanceOf(wallet.address);
  const lxonBalance = await lxon.balanceOf(wallet.address);
  const wethDecimals = await weth.decimals();
  const lxonDecimals = await lxon.decimals();

  console.log("WETH:", Number(ethers.formatUnits(wethBalance, wethDecimals)).toFixed(4));
  console.log("LXON:", Number(ethers.formatUnits(lxonBalance, lxonDecimals)).toFixed(4));

  // If no LXON, transfer from the address that has 1B LXON
  if (lxonBalance === 0n) {
    console.log("\n=== No LXON in deployer wallet ===");
    console.log("Transferring LXON from the address with 1B LXON");
    console.log("Address: 0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b");
    console.log("Amount: 100M LXON");

    if (!LXON_1B_PRIVATE_KEY) {
      console.log("❌ Need LXON_1B_PRIVATE_KEY in .env");
      return;
    }

    const walletWith1B = new ethers.Wallet(LXON_1B_PRIVATE_KEY, provider);
    const lxonWith1B = new ethers.Contract(LXON_ADDRESS, LXON_ABI, walletWith1B);

    const amountToTransfer = ethers.parseUnits("100000000", 6); // 100M LXON

    try {
      const tx = await lxonWith1B.transfer(wallet.address, amountToTransfer);
      console.log("Transfer transaction:", tx.hash);
      await tx.wait();
      console.log("✅ 100M LXON transferred to deployer");
    } catch (error) {
      console.error("❌ Failed to transfer LXON:", error.message);
      console.log("Cannot add liquidity without LXON tokens");
      return;
    }

    // Update balance
    const newLxonBalance = await lxon.balanceOf(wallet.address);
    console.log("New LXON balance:", Number(ethers.formatUnits(newLxonBalance, lxonDecimals)).toFixed(4));
  }

  // Approve tokens
  console.log("\n=== Approving Tokens ===");
  const wethApprove = await weth.approve(PAIR_ADDRESS, ethers.MaxUint256);
  console.log("WETH approve:", wethApprove.hash);
  await wethApprove.wait();
  console.log("✅ WETH approved");

  const lxonApprove = await lxon.approve(PAIR_ADDRESS, ethers.MaxUint256);
  console.log("LXON approve:", lxonApprove.hash);
  await lxonApprove.wait();
  console.log("✅ LXON approved");

  // Transfer tokens to pair
  console.log("\n=== Transferring Tokens to Pair ===");
  const lxonFinalBalance = await lxon.balanceOf(wallet.address);
  const wethFinalBalance = await weth.balanceOf(wallet.address);

  const lxonToAdd = lxonFinalBalance / 2n;
  const wethToAdd = wethFinalBalance / 2n;

  console.log("Adding LXON:", Number(ethers.formatUnits(lxonToAdd, lxonDecimals)).toFixed(4));
  console.log("Adding WETH:", Number(ethers.formatUnits(wethToAdd, wethDecimals)).toFixed(4));

  const lxonTransfer = await lxon.transfer(PAIR_ADDRESS, lxonToAdd);
  console.log("LXON transfer:", lxonTransfer.hash);
  await lxonTransfer.wait();
  console.log("✅ LXON transferred");

  const wethTransfer = await weth.transfer(PAIR_ADDRESS, wethToAdd);
  console.log("WETH transfer:", wethTransfer.hash);
  await wethTransfer.wait();
  console.log("✅ WETH transferred");

  // Mint LP tokens
  console.log("\n=== Minting LP Tokens ===");
  try {
    const mintTx = await pair.mint(wallet.address);
    console.log("Mint transaction:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ LP tokens minted");
  } catch (error) {
    console.error("❌ Failed to mint LP tokens:", error.message);
    return;
  }

  // Verify
  console.log("\n=== Verification ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const lpBalance = await pair.balanceOf(wallet.address);
  const pairDecimals = await pair.decimals();

  console.log("Reserve0:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("Reserve1:", ethers.formatUnits(reserve1, lxonDecimals));
  console.log("LP tokens:", ethers.formatUnits(lpBalance, pairDecimals));

  const price = Number(ethers.formatUnits(reserve0, wethDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals));
  console.log("Price:", price.toFixed(6), "WETH per LXON");

  console.log("\n✅ Liquidity added successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
