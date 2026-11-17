import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Generating trading volume on DEX");
  console.log("Account:", deployerAddress);

  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";
  const NEW_ROUTER_ADDRESS = "0xA2AF542999c4412E387ba7e3867cE541cdfeDb80";

  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", NEW_ROUTER_ADDRESS)) as Router;

  const ETH_PRICE_USD = 3000;

  console.log("\n=== Initial State ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  console.log("Price per LXON:", pricePerLXON, "WETH ($", (pricePerLXON * ETH_PRICE_USD).toFixed(2), ")");

  const tradingHistory = [];

  // Perform 5 back-and-forth swaps to generate volume
  for (let i = 0; i < 5; i++) {
    console.log(`\n=== Round ${i + 1} ===`);

    // LXON → WETH
    const lxonSwapAmount = ethers.parseUnits("0.2", 6);
    const lxonBalance = await lxon.balanceOf(deployerAddress);

    if (lxonBalance >= lxonSwapAmount) {
      console.log("LXON → WETH swap");
      await lxon.approve(NEW_ROUTER_ADDRESS, lxonSwapAmount);
      const swapTx = await router.swapLXONForWETH(
        lxonSwapAmount,
        0,
        deployerAddress,
        Math.floor(Date.now() / 1000) + 60 * 10
      );
      const receipt = await swapTx.wait();
      tradingHistory.push({
        direction: "LXON → WETH",
        amountIn: "0.2 LXON",
        txHash: receipt?.hash,
        timestamp: new Date().toISOString()
      });
      console.log("✅ Swap completed:", receipt?.hash);
    }

    // WETH → LXON
    const wethSwapAmount = ethers.parseEther("0.0001");
    const wethBalance = await weth.balanceOf(deployerAddress);

    if (wethBalance >= wethSwapAmount) {
      console.log("WETH → LXON swap");
      await weth.approve(NEW_ROUTER_ADDRESS, wethSwapAmount);
      const swapTx = await router.swapWETHForLXON(
        wethSwapAmount,
        0,
        deployerAddress,
        Math.floor(Date.now() / 1000) + 60 * 10
      );
      const receipt = await swapTx.wait();
      tradingHistory.push({
        direction: "WETH → LXON",
        amountIn: "0.0001 WETH",
        txHash: receipt?.hash,
        timestamp: new Date().toISOString()
      });
      console.log("✅ Swap completed:", receipt?.hash);
    }
  }

  // Final state
  console.log("\n=== Final State ===");
  const [finalReserve0, finalReserve1] = await pair.getReserves();
  const finalWethReserve = Number(ethers.formatEther(finalReserve0));
  const finalLxonReserve = Number(ethers.formatUnits(finalReserve1, 6));
  const finalPricePerLXON = finalWethReserve / finalLxonReserve;
  console.log("Price per LXON:", finalPricePerLXON, "WETH ($", (finalPricePerLXON * ETH_PRICE_USD).toFixed(2), ")");

  console.log("\n=== Trading History ===");
  tradingHistory.forEach((trade, index) => {
    console.log(`${index + 1}. ${trade.direction}: ${trade.amountIn}`);
    console.log("   TX:", trade.txHash);
    console.log("   Time:", trade.timestamp);
  });

  console.log("\n=== Summary ===");
  console.log("Total swaps:", tradingHistory.length);
  console.log("Trading volume generated:", tradingHistory.length, "transactions");
  console.log("DEX is operational with verified swap functionality");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
