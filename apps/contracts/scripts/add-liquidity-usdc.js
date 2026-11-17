const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Add Liquidity for LXON/USDC at $2/LXON ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const usdcAddress = process.env.USDC_ADDRESS;
  const pairAddress = process.env.DEX_PAIR_USDC;

  console.log("LXON Address:", lxonAddress);
  console.log("USDC Address:", usdcAddress);
  console.log("Pair Address:", pairAddress);

  const ERC20ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function transfer(address to, uint256 amount) external returns (bool)"
  ];

  const PairABI = [
    "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
    "function mint(address to) external returns (uint256)"
  ];

  const lxon = new ethers.Contract(lxonAddress, ERC20ABI, deployer);
  const usdc = new ethers.Contract(usdcAddress, ERC20ABI, deployer);
  const pair = new ethers.Contract(pairAddress, PairABI, deployer);

  const lxonDecimals = await lxon.decimals();
  const usdcDecimals = await usdc.decimals();

  const lxonBalance = await lxon.balanceOf(deployer.address);
  const usdcBalance = await usdc.balanceOf(deployer.address);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));
  console.log("USDC balance:", ethers.formatUnits(usdcBalance, usdcDecimals));

  // Target: $2/LXON = 2 USDC per LXON
  const targetPrice = 2; // 2 USDC per LXON
  const usdcToUse = ethers.parseUnits("111600000", 18); // Use all 111.6M USDC (18 decimals)
  const lxonToUse = usdcToUse / ethers.parseUnits(targetPrice.toString(), usdcDecimals) * ethers.parseUnits("1", lxonDecimals);

  console.log("\n=== Liquidity Calculation ===");
  console.log("Target price:", targetPrice, "USDC per LXON = $2/LXON");
  console.log("USDC to add:", ethers.formatUnits(usdcToUse, usdcDecimals));
  console.log("LXON to add:", ethers.formatUnits(lxonToUse, lxonDecimals));

  if (lxonToUse > lxonBalance) {
    console.log("❌ Not enough LXON balance");
    console.log("Need:", ethers.formatUnits(lxonToUse, lxonDecimals));
    console.log("Have:", ethers.formatUnits(lxonBalance, lxonDecimals));
    return;
  }

  // Approve
  console.log("\n=== Approving ===");
  await lxon.approve(pairAddress, ethers.MaxUint256);
  await usdc.approve(pairAddress, ethers.MaxUint256);
  console.log("✅ Approved");

  // Transfer
  console.log("\n=== Transferring ===");
  await lxon.transfer(pairAddress, lxonToUse);
  await usdc.transfer(pairAddress, usdcToUse);
  console.log("✅ Transferred");

  // Mint
  console.log("\n=== Minting LP ===");
  const tx = await pair.mint(deployer.address);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ LP tokens minted");

  // Verify
  const [reserve0, reserve1] = await pair.getReserves();
  const newPrice = Number(ethers.formatUnits(reserve0, usdcDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals));
  console.log("\n=== Verification ===");
  console.log("New USDC reserve:", ethers.formatUnits(reserve0, usdcDecimals));
  console.log("New LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));
  console.log("New price:", newPrice, "USDC per LXON");
  console.log("New price in USD:", newPrice, "USD per LXON");

  console.log("\n✅ Liquidity added for $2/LXON with USDC!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
