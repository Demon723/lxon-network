import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding correct liquidity to Pair for $1.50 price target");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;

  // Target: $1.50 per LXON, TVL $62,700
  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000;
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD; // 0.0005

  // Target amounts for $62,700 TVL
  const TARGET_LXON = 20900; // 20,900 LXON
  const TARGET_WETH = TARGET_LXON * TARGET_WETH_PER_LXON; // 10.45 WETH

  console.log("\n=== Target Liquidity ===");
  console.log("Target LXON:", TARGET_LXON);
  console.log("Target WETH:", TARGET_WETH);
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Target TVL: $", (TARGET_LXON * TARGET_PRICE_USD).toFixed(2));

  // Check current state
  const currentLXONBalance = await lxon.balanceOf(PAIR_ADDRESS);
  const currentWETHBalance = await weth.balanceOf(PAIR_ADDRESS);
  const deployerLXONBalance = await lxon.balanceOf(deployerAddress);
  const deployerWETHBalance = await weth.balanceOf(deployerAddress);
  const deployerETHBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Current State ===");
  console.log("Pair LXON balance:", ethers.formatUnits(currentLXONBalance, 6));
  console.log("Pair WETH balance:", ethers.formatEther(currentWETHBalance));
  console.log("Deployer LXON balance:", ethers.formatUnits(deployerLXONBalance, 6));
  console.log("Deployer WETH balance:", ethers.formatEther(deployerWETHBalance));
  console.log("Deployer ETH balance:", ethers.formatEther(deployerETHBalance));

  // Calculate additional amounts needed
  const additionalLXON = ethers.parseUnits((TARGET_LXON - Number(ethers.formatUnits(currentLXONBalance, 6))).toString(), 6);
  const additionalWETH = ethers.parseEther((TARGET_WETH - Number(ethers.formatEther(currentWETHBalance))).toString());

  console.log("\n=== Additional Liquidity Needed ===");
  console.log("Additional LXON:", ethers.formatUnits(additionalLXON, 6));
  console.log("Additional WETH:", ethers.formatEther(additionalWETH));

  // Check if deployer has enough balance
  if (deployerLXONBalance < additionalLXON) {
    console.log("\nERROR: Insufficient LXON balance");
    console.log("Needed:", ethers.formatUnits(additionalLXON, 6));
    console.log("Have:", ethers.formatUnits(deployerLXONBalance, 6));
    return;
  }

  // Deposit ETH to get WETH if needed
  if (deployerWETHBalance < additionalWETH) {
    const wethNeeded = additionalWETH - deployerWETHBalance;
    console.log("\nDepositing ETH to get WETH...");
    console.log("WETH needed:", ethers.formatEther(wethNeeded));
    if (deployerETHBalance < wethNeeded) {
      console.log("ERROR: Insufficient ETH balance");
      console.log("Needed:", ethers.formatEther(wethNeeded));
      console.log("Have:", ethers.formatEther(deployerETHBalance));
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Transfer additional tokens to pair
  console.log("\nTransferring additional tokens to pair...");
  await lxon.transfer(PAIR_ADDRESS, additionalLXON);
  await weth.transfer(PAIR_ADDRESS, additionalWETH);
  console.log("Tokens transferred");

  // Mint LP tokens
  console.log("\nMinting LP tokens...");
  const mintTx = await pair.mint(deployerAddress);
  const receipt = await mintTx.wait();
  console.log("LP tokens minted successfully");
  console.log("Transaction hash:", receipt?.hash);

  // Check final state
  const finalLXONBalance = await lxon.balanceOf(PAIR_ADDRESS);
  const finalWETHBalance = await weth.balanceOf(PAIR_ADDRESS);
  const [reserve0, reserve1] = await pair.getReserves();
  const lpBalance = await pair.balanceOf(deployerAddress);

  console.log("\n=== Final State ===");
  console.log("Pair LXON balance:", ethers.formatUnits(finalLXONBalance, 6));
  console.log("Pair WETH balance:", ethers.formatEther(finalWETHBalance));
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));
  console.log("LP tokens received:", ethers.formatEther(lpBalance));

  // Calculate price
  // Since token0=WETH (18 decimals) and token1=LXON (6 decimals)
  // price per LXON = (reserve0 / 1e18) / (reserve1 / 1e6)
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;
  const tvlUSD = (lxonReserve * priceUSD) + (wethReserve * ETH_PRICE_USD);

  console.log("\n=== Price Calculation ===");
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD.toFixed(2));
  console.log("Target price: $", TARGET_PRICE_USD);
  console.log("Price deviation:", ((priceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");
  console.log("TVL: $", tvlUSD.toFixed(2));
  console.log("Target TVL: $", (TARGET_LXON * TARGET_PRICE_USD).toFixed(2));

  console.log("\n=== Contract Addresses ===");
  console.log("Pair:", PAIR_ADDRESS);
  console.log("Router: 0x0De021F0caA907e11f06a2bd78767b1a3557D8A3");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
