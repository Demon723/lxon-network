import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deploying final correct Pair with $1.50 price");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const newPairAddress = "0x896daaADC5992D6F77021aB3100a64253aEa73Ad";
  const newRouterAddress = "0x7d5Bb5E0A55766dA8a501DDD35c2Ad1573164Ea9";

  // Connect to existing contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", newPairAddress)) as Pair;

  // Target price: $1.50 per LXON
  // Assuming ETH/WETH is ~$3,000
  // Target: 1 LXON = $1.50 = 0.0005 WETH
  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000;
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD;

  console.log("\n=== Price Target ===");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Target WETH per LXON:", TARGET_WETH_PER_LXON);

  console.log("\n=== Using Existing Contracts ===");
  console.log("Pair:", newPairAddress);
  console.log("Router:", newRouterAddress);

  // Calculate correct liquidity amounts for $1.50 price
  // For first liquidity, we need: 10,000 LXON and 5 WETH
  const LXON_AMOUNT = ethers.parseUnits("10000", 6);
  const WETH_AMOUNT = ethers.parseEther("5");

  console.log("\n=== Adding Liquidity ===");
  console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
  console.log("WETH amount:", ethers.formatEther(WETH_AMOUNT));

  // Check balances
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  const wethBalance = await weth.balanceOf(deployerAddress);
  const ethBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  if (lxonBalance < LXON_AMOUNT) {
    console.log("Insufficient LXON balance");
    return;
  }

  // Deposit ETH to get WETH if needed
  if (wethBalance < WETH_AMOUNT) {
    console.log("Depositing ETH to get WETH...");
    const wethNeeded = WETH_AMOUNT - wethBalance;
    if (ethBalance < wethNeeded) {
      console.log("Insufficient ETH balance");
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Transfer tokens directly to pair
  console.log("Transferring tokens to pair...");
  await lxon.transfer(newPairAddress, LXON_AMOUNT);
  await weth.transfer(newPairAddress, WETH_AMOUNT);
  console.log("Tokens transferred");

  // Mint LP tokens directly (first liquidity)
  console.log("Minting LP tokens...");
  const mintTx = await newPair.mint(deployerAddress);
  const receipt = await mintTx.wait();
  console.log("LP tokens minted successfully");
  console.log("Transaction hash:", receipt?.hash);

  // Log final state
  const lpBalance = await newPair.balanceOf(deployerAddress);
  const [reserve0, reserve1] = await newPair.getReserves();

  const newPrice = reserve0 > 0n ? Number(reserve1) / Number(reserve0) : 0;
  const newPriceUSD = newPrice * ETH_PRICE_USD;

  console.log("\n=== Final State ===");
  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Price:", newPrice, "WETH per LXON");
  console.log("Price: $", newPriceUSD, "per LXON");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Price deviation:", ((newPriceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");

  console.log("\n=== Final Contract Addresses ===");
  console.log("Pair:", newPairAddress);
  console.log("Router:", newRouterAddress);
  console.log("\n⚠️  UPDATE YOUR FRONTEND AND DOCUMENTATION TO USE THESE ADDRESSES!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
