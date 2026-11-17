import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adjusting liquidity to reach $1.50 price target");
  console.log("Account:", deployerAddress);

  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";

  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const newPair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;

  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000;
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD;

  console.log("\n=== Current State ===");
  const currentLXON = await lxon.balanceOf(NEW_PAIR_ADDRESS);
  const currentWETH = await weth.balanceOf(NEW_PAIR_ADDRESS);
  const [reserve0, reserve1] = await newPair.getReserves();

  const lxonAmount = Number(ethers.formatUnits(currentLXON, 6));
  const wethAmount = Number(ethers.formatEther(currentWETH));
  const currentPrice = wethAmount / lxonAmount;
  const currentPriceUSD = currentPrice * ETH_PRICE_USD;

  console.log("LXON in pair:", lxonAmount);
  console.log("WETH in pair:", wethAmount);
  console.log("Current price: $", currentPriceUSD.toFixed(2));
  console.log("Target price: $", TARGET_PRICE_USD);

  // Calculate required WETH for target price
  const targetWETH = lxonAmount * TARGET_WETH_PER_LXON;
  const additionalWETH = targetWETH - wethAmount;

  console.log("\n=== Required Adjustment ===");
  console.log("Target WETH:", targetWETH);
  console.log("Additional WETH needed:", additionalWETH);

  // Check deployer WETH balance
  const deployerWETH = await weth.balanceOf(deployerAddress);
  const deployerETH = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Deployer Balances ===");
  console.log("WETH:", ethers.formatEther(deployerWETH));
  console.log("ETH:", ethers.formatEther(deployerETH));

  const additionalWETHBN = ethers.parseEther(additionalWETH.toString());

  // Deposit ETH to get WETH if needed
  if (deployerWETH < additionalWETHBN) {
    const wethNeeded = additionalWETHBN - deployerWETH;
    console.log("\nDepositing ETH to get WETH...");
    console.log("WETH needed:", ethers.formatEther(wethNeeded));
    if (deployerETH < wethNeeded) {
      console.log("ERROR: Insufficient ETH balance");
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Transfer additional WETH to pair
  console.log("\nTransferring additional WETH to pair...");
  const transferTx = await weth.transfer(NEW_PAIR_ADDRESS, additionalWETHBN);
  await transferTx.wait();
  console.log("WETH transferred");

  // Sync reserves to reflect new balances
  console.log("\nSyncing reserves...");
  const syncTx = await newPair.sync();
  await syncTx.wait();
  console.log("Reserves synced");

  // Mint additional LP tokens
  console.log("\nMinting additional LP tokens...");
  const mintTx = await newPair.mint(deployerAddress);
  await mintTx.wait();
  console.log("LP tokens minted");

  // Verify final state
  const finalLXON = await lxon.balanceOf(NEW_PAIR_ADDRESS);
  const finalWETH = await weth.balanceOf(NEW_PAIR_ADDRESS);
  const [finalReserve0, finalReserve1] = await newPair.getReserves();
  const lpBalance = await newPair.balanceOf(deployerAddress);

  console.log("\n=== Final State ===");
  console.log("LXON in pair:", ethers.formatUnits(finalLXON, 6));
  console.log("WETH in pair:", ethers.formatEther(finalWETH));
  console.log("Reserve0 (WETH):", ethers.formatEther(finalReserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(finalReserve1, 6));
  console.log("LP tokens received:", ethers.formatEther(lpBalance));

  // Calculate final price
  const finalWethReserve = Number(ethers.formatEther(finalReserve0));
  const finalLxonReserve = Number(ethers.formatUnits(finalReserve1, 6));
  const finalPrice = finalWethReserve / finalLxonReserve;
  const finalPriceUSD = finalPrice * ETH_PRICE_USD;
  const tvlUSD = (finalLxonReserve * finalPriceUSD) + (finalWethReserve * ETH_PRICE_USD);

  console.log("\n=== Price Calculation ===");
  console.log("Price per LXON:", finalPrice, "WETH");
  console.log("Price per LXON: $", finalPriceUSD.toFixed(2));
  console.log("Target price: $", TARGET_PRICE_USD);
  console.log("Price deviation:", ((finalPriceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");
  console.log("TVL: $", tvlUSD.toFixed(2));

  console.log("\n=== Contract Addresses ===");
  console.log("New Pair:", NEW_PAIR_ADDRESS);
  console.log("New Router: 0xA2AF542999c4412E387ba7e3867cE541cdfeDb80");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
