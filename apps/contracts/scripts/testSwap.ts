import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Testing swap on DEX");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
  const ROUTER_ADDRESS = "0x0De021F0caA907e11f06a2bd78767b1a3557D8A3";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", ROUTER_ADDRESS)) as Router;

  const ETH_PRICE_USD = 3000;

  console.log("\n=== Current State ===");
  const [reserve0, reserve1] = await pair.getReserves();
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  console.log("Price per LXON:", pricePerLXON, "WETH ($", (pricePerLXON * ETH_PRICE_USD).toFixed(2), ")");

  // Test swap: LXON -> WETH
  const swapAmount = ethers.parseUnits("100", 6); // 100 LXON
  console.log("\n=== Testing Swap: 100 LXON -> WETH ===");
  console.log("Swap amount:", ethers.formatUnits(swapAmount, 6), "LXON");

  // Check LXON balance
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

  if (lxonBalance < swapAmount) {
    console.log("ERROR: Insufficient LXON balance for swap test");
    return;
  }

  // Approve router
  console.log("Approving router...");
  const approveTx = await lxon.approve(ROUTER_ADDRESS, swapAmount);
  await approveTx.wait();
  console.log("Router approved");

  // Get expected output
  const amountOut = await pair.getAmountOut(swapAmount, reserve1, reserve0);
  console.log("Expected WETH output:", ethers.formatEther(amountOut));

  // Perform swap
  console.log("Performing swap...");
  const swapTx = await router.swapExactTokensForTokens(
    swapAmount,
    0, // Accept any amount
    [LXON_ADDRESS, WETH_ADDRESS],
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
  console.log("WETH received:", ethers.formatEther(finalWETHBalance));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
