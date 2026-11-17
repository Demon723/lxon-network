import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Testing WETH → LXON swap on fixed DEX");
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

  console.log("\n=== Current State ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  console.log("Price per LXON:", pricePerLXON, "WETH ($", (pricePerLXON * ETH_PRICE_USD).toFixed(2), ")");

  // Test swap: 0.0002 WETH → LXON
  const swapAmount = ethers.parseEther("0.0002");
  console.log("\n=== Testing Swap: 0.0002 WETH → LXON ===");
  console.log("Swap amount:", ethers.formatEther(swapAmount), "WETH");

  // Check WETH balance
  const wethBalance = await weth.balanceOf(deployerAddress);
  console.log("WETH balance:", ethers.formatEther(wethBalance));

  if (wethBalance < swapAmount) {
    console.log("ERROR: Insufficient WETH balance for swap test");
    console.log("Needed:", ethers.formatEther(swapAmount));
    console.log("Have:", ethers.formatEther(wethBalance));
    return;
  }

  // Approve router
  console.log("Approving router...");
  const approveTx = await weth.approve(NEW_ROUTER_ADDRESS, swapAmount);
  await approveTx.wait();
  console.log("Router approved");

  // Get expected output
  const amountOut = await pair.getAmountOut(swapAmount, reserve0, reserve1);
  console.log("Expected LXON output:", ethers.formatUnits(amountOut, 6));

  // Perform swap using Router
  console.log("Performing swap via Router...");
  const swapTx = await router.swapWETHForLXON(
    swapAmount,
    0, // Accept any amount
    deployerAddress,
    Math.floor(Date.now() / 1000) + 60 * 10 // 10 minutes deadline
  );
  const receipt = await swapTx.wait();
  console.log("Swap completed");
  console.log("Transaction hash:", receipt?.hash);

  // Check final balances
  const finalLXONBalance = await lxon.balanceOf(deployerAddress);
  const finalWETHBalance = await weth.balanceOf(deployerAddress);
  const [finalReserve0, finalReserve1] = await pair.getReserves();

  console.log("\n=== Final State ===");
  console.log("LXON balance:", ethers.formatUnits(finalLXONBalance, 6));
  console.log("WETH balance:", ethers.formatEther(finalWETHBalance));
  console.log("Reserve0 (WETH):", ethers.formatEther(finalReserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(finalReserve1, 6));

  // Calculate new price
  const newWethReserve = Number(ethers.formatEther(finalReserve0));
  const newLxonReserve = Number(ethers.formatUnits(finalReserve1, 6));
  const newPricePerLXON = newWethReserve / newLxonReserve;
  console.log("New price per LXON:", newPricePerLXON, "WETH ($", (newPricePerLXON * ETH_PRICE_USD).toFixed(2), ")");

  console.log("\n=== Swap Test Result ===");
  console.log("✅ Swap successful");
  console.log("LXON received:", ethers.formatUnits(finalLXONBalance, 6));
  console.log("WETH spent:", ethers.formatEther(wethBalance - finalWETHBalance));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
