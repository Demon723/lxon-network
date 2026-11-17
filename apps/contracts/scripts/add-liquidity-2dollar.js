const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Add Liquidity for $2/LXON ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const wethMintableAddress = process.env.WETH_MINTABLE;
  const pairAddress = process.env.DEX_PAIR_2DOLLAR;

  console.log("LXON address:", lxonAddress);
  console.log("WETH Mintable address:", wethMintableAddress);
  console.log("Pair address:", pairAddress);

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
  const weth = new ethers.Contract(wethMintableAddress, ERC20ABI, deployer);
  const pair = new ethers.Contract(pairAddress, PairABI, deployer);

  const lxonDecimals = await lxon.decimals();
  const wethDecimals = await weth.decimals();

  const lxonBalance = await lxon.balanceOf(deployer.address);
  const wethBalance = await weth.balanceOf(deployer.address);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, lxonDecimals));
  console.log("WETH balance:", ethers.formatUnits(wethBalance, wethDecimals));

  // Target: $2/LXON = 1.33 WETH per LXON
  const targetPrice = 1.33;
  const wethToUse = ethers.parseEther("111600000"); // Use all 111.6M WETH
  const lxonToUse = wethToUse / ethers.parseUnits(targetPrice.toString(), wethDecimals) * ethers.parseUnits("1", lxonDecimals);

  console.log("\n=== Liquidity Calculation ===");
  console.log("Target price:", targetPrice, "WETH per LXON = $2/LXON");
  console.log("WETH to add:", ethers.formatUnits(wethToUse, wethDecimals));
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
  await weth.approve(pairAddress, ethers.MaxUint256);
  console.log("✅ Approved");

  // Transfer
  console.log("\n=== Transferring ===");
  await lxon.transfer(pairAddress, lxonToUse);
  await weth.transfer(pairAddress, wethToUse);
  console.log("✅ Transferred");

  // Mint
  console.log("\n=== Minting LP ===");
  const tx = await pair.mint(deployer.address);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ LP tokens minted");

  // Verify
  const [reserve0, reserve1] = await pair.getReserves();
  const newPrice = Number(ethers.formatUnits(reserve0, wethDecimals)) / Number(ethers.formatUnits(reserve1, lxonDecimals));
  console.log("\n=== Verification ===");
  console.log("New WETH reserve:", ethers.formatUnits(reserve0, wethDecimals));
  console.log("New LXON reserve:", ethers.formatUnits(reserve1, lxonDecimals));
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price in USD:", newPrice * 1.5, "USD per LXON");

  console.log("\n✅ Liquidity added for $2/LXON!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
