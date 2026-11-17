import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

// Helper function for delay
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Generating daily trading volume on DEX");
  console.log("Account:", deployerAddress);
  console.log("Date:", new Date().toISOString());

  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";
  const NEW_ROUTER_ADDRESS = "0xA2AF542999c4412E387ba7e3867cE541cdfeDb80";

  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", NEW_ROUTER_ADDRESS)) as Router;

  const ETH_PRICE_USD = 3000;
  const TARGET_PRICE_USD = 1.50;
  const PRICE_THRESHOLD = 1.498; // More aggressive - trigger buyback closer to target

  console.log("\n=== Initial State ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;
  console.log("Price per LXON:", pricePerLXON, "WETH ($", priceUSD.toFixed(2), ")");
  console.log("TVL: $", (lxonReserve * pricePerLXON * ETH_PRICE_USD + wethReserve * ETH_PRICE_USD).toFixed(2));
  console.log("Price target: $", TARGET_PRICE_USD);
  console.log("Price threshold: $", PRICE_THRESHOLD);

  const tradingHistory = [];
  let totalVolumeUSD = 0;

  // Two-way swaps to maintain price floor
  const numSwaps = 30;
  const lxonSwapAmount = ethers.parseUnits("0.1", 6);
  const wethSwapAmount = ethers.parseEther("0.0002"); // Moderate WETH amount for buyback
  const minWETHBalance = ethers.parseEther("0.001"); // Minimum WETH to maintain

  for (let i = 0; i < numSwaps; i++) {
    console.log(`\n=== Swap ${i + 1}/${numSwaps} ===`);

    // Check current price and balances
    const [currentReserve0, currentReserve1] = await pair.getReserves();
    const currentWethReserve = Number(ethers.formatEther(currentReserve0));
    const currentLxonReserve = Number(ethers.formatUnits(currentReserve1, 6));
    const currentPricePerLXON = currentWethReserve / currentLxonReserve;
    const currentPriceUSD = currentPricePerLXON * ETH_PRICE_USD;
    const wethBalance = await weth.balanceOf(deployerAddress);
    const lxonBalance = await lxon.balanceOf(deployerAddress);

    console.log("Current price: $", currentPriceUSD.toFixed(2));
    console.log("WETH balance:", ethers.formatEther(wethBalance));
    console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

    // Strategy: If WETH is low, sell LXON to replenish. If price is low, buy back.
    if (wethBalance < minWETHBalance) {
      // Need to replenish WETH - sell LXON
      console.log("LXON → WETH swap (replenishing WETH balance)");
      if (lxonBalance >= lxonSwapAmount) {
        try {
          const wethBalanceBefore = await weth.balanceOf(deployerAddress);
          await lxon.approve(NEW_ROUTER_ADDRESS, lxonSwapAmount);
          const swapTx = await router.swapLXONForWETH(
            lxonSwapAmount,
            0,
            deployerAddress,
            Math.floor(Date.now() / 1000) + 60 * 10
          );
          const receipt = await swapTx.wait();
          const wethBalanceAfter = await weth.balanceOf(deployerAddress);
          const wethReceived = wethBalanceAfter - wethBalanceBefore;
          const volumeUSD = Number(ethers.formatEther(wethReceived)) * ETH_PRICE_USD;
          totalVolumeUSD += volumeUSD;
          tradingHistory.push({
            direction: "LXON → WETH",
            amountIn: "0.1 LXON",
            amountOut: ethers.formatEther(wethReceived) + " WETH",
            volumeUSD: volumeUSD,
            txHash: receipt?.hash,
            timestamp: new Date().toISOString()
          });
          console.log("✅ Swap completed:", receipt?.hash);
          console.log("   WETH received:", ethers.formatEther(wethReceived));
          console.log("   Volume: $", volumeUSD.toFixed(2));
          await delay(1000);
        } catch (error) {
          console.log("❌ Swap failed");
          console.log("   Continuing to next swap...");
          await delay(2000);
        }
      } else {
        console.log("⏭️  Skipping (insufficient LXON balance)");
        break;
      }
    } else if (currentPriceUSD < PRICE_THRESHOLD) {
      // Price is too low - buy LXON with WETH to raise price
      console.log("WETH → LXON swap (price below threshold - buyback)");
      if (wethBalance >= wethSwapAmount) {
        try {
          const lxonBalanceBefore = await lxon.balanceOf(deployerAddress);
          await weth.approve(NEW_ROUTER_ADDRESS, wethSwapAmount);
          const swapTx = await router.swapWETHForLXON(
            wethSwapAmount,
            0,
            deployerAddress,
            Math.floor(Date.now() / 1000) + 60 * 10
          );
          const receipt = await swapTx.wait();
          const lxonBalanceAfter = await lxon.balanceOf(deployerAddress);
          const lxonReceived = lxonBalanceAfter - lxonBalanceBefore;
          const volumeUSD = Number(ethers.formatEther(wethSwapAmount)) * ETH_PRICE_USD;
          totalVolumeUSD += volumeUSD;
          tradingHistory.push({
            direction: "WETH → LXON",
            amountIn: ethers.formatEther(wethSwapAmount) + " WETH",
            amountOut: ethers.formatUnits(lxonReceived, 6) + " LXON",
            volumeUSD: volumeUSD,
            txHash: receipt?.hash,
            timestamp: new Date().toISOString()
          });
          console.log("✅ Buyback completed:", receipt?.hash);
          console.log("   LXON received:", ethers.formatUnits(lxonReceived, 6));
          console.log("   Volume: $", volumeUSD.toFixed(2));
          console.log("   Price should increase after this swap");
          await delay(1000);
        } catch (error) {
          console.log("❌ Buyback failed");
          console.log("   Continuing to next swap...");
          await delay(2000);
        }
      } else {
        console.log("⏭️  Skipping buyback (insufficient WETH balance)");
        console.log("   Current balance:", ethers.formatEther(wethBalance), "WETH");
        console.log("   Required:", ethers.formatEther(wethSwapAmount), "WETH");
        break;
      }
    } else {
      // Price is good and WETH is sufficient - sell LXON for volume
      console.log("LXON → WETH swap (price is above threshold)");
      if (lxonBalance >= lxonSwapAmount) {
        try {
          const wethBalanceBefore = await weth.balanceOf(deployerAddress);
          await lxon.approve(NEW_ROUTER_ADDRESS, lxonSwapAmount);
          const swapTx = await router.swapLXONForWETH(
            lxonSwapAmount,
            0,
            deployerAddress,
            Math.floor(Date.now() / 1000) + 60 * 10
          );
          const receipt = await swapTx.wait();
          const wethBalanceAfter = await weth.balanceOf(deployerAddress);
          const wethReceived = wethBalanceAfter - wethBalanceBefore;
          const volumeUSD = Number(ethers.formatEther(wethReceived)) * ETH_PRICE_USD;
          totalVolumeUSD += volumeUSD;
          tradingHistory.push({
            direction: "LXON → WETH",
            amountIn: "0.1 LXON",
            amountOut: ethers.formatEther(wethReceived) + " WETH",
            volumeUSD: volumeUSD,
            txHash: receipt?.hash,
            timestamp: new Date().toISOString()
          });
          console.log("✅ Swap completed:", receipt?.hash);
          console.log("   WETH received:", ethers.formatEther(wethReceived));
          console.log("   Volume: $", volumeUSD.toFixed(2));
          await delay(1000);
        } catch (error) {
          console.log("❌ Swap failed");
          console.log("   Continuing to next swap...");
          await delay(2000);
        }
      } else {
        console.log("⏭️  Skipping (insufficient LXON balance)");
        console.log("   Current balance:", ethers.formatUnits(lxonBalance, 6), "LXON");
        break;
      }
    }
  }

  // Final state
  console.log("\n=== Final State ===");
  const [finalReserve0, finalReserve1] = await pair.getReserves();
  const finalWethReserve = Number(ethers.formatEther(finalReserve0));
  const finalLxonReserve = Number(ethers.formatUnits(finalReserve1, 6));
  const finalPricePerLXON = finalWethReserve / finalLxonReserve;
  const finalPriceUSD = finalPricePerLXON * ETH_PRICE_USD;
  console.log("Price per LXON:", finalPricePerLXON, "WETH ($", finalPriceUSD.toFixed(2), ")");
  console.log("TVL: $", (finalLxonReserve * finalPricePerLXON * ETH_PRICE_USD + finalWethReserve * ETH_PRICE_USD).toFixed(2));
  console.log("Price target status:", finalPriceUSD >= TARGET_PRICE_USD ? "✅ ABOVE TARGET" : "❌ BELOW TARGET");

  console.log("\n=== Trading History ===");
  tradingHistory.forEach((trade, index) => {
    console.log(`${index + 1}. ${trade.direction}: ${trade.amountIn} → ${trade.amountOut}`);
    console.log("   Volume: $", trade.volumeUSD.toFixed(2));
    console.log("   TX:", trade.txHash);
    console.log("   Time:", trade.timestamp);
  });

  console.log("\n=== Summary ===");
  console.log("Total swaps:", tradingHistory.length);
  console.log("Total volume generated: $", totalVolumeUSD.toFixed(2));
  console.log("Target: $1,000+ daily");
  console.log("Progress:", ((totalVolumeUSD / 1000) * 100).toFixed(2), "%");
  console.log("DEX is operational with verified swap functionality");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
