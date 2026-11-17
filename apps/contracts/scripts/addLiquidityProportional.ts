import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding liquidity with account:", deployerAddress);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Contract addresses from deployment
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7";
  const ROUTER_ADDRESS = "0x92F4D1236026F23967eBd213547FE18606AE8dD5";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", ROUTER_ADDRESS)) as Router;

  console.log("Connected to contracts:");
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);
  console.log("Pair:", PAIR_ADDRESS);
  console.log("Router:", ROUTER_ADDRESS);

  // Check current reserves
  const [reserve0, reserve1] = await pair.getReserves();
  console.log("\n=== Current Reserves ===");
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));

  // Calculate optimal amounts based on existing reserves
  // Current ratio: reserve0 / reserve1
  // We want to add liquidity in the same ratio
  const currentRatio = (reserve0 > 0n && reserve1 > 0n) ? Number(reserve1) / Number(reserve0) : 0;
  console.log("Current WETH/LXON ratio:", currentRatio);

  // Add liquidity - use small amounts to bootstrap
  const INITIAL_LXON = ethers.parseUnits("100", 6); // 100 LXON
  const INITIAL_WETH = ethers.parseEther("0.001"); // 0.001 WETH (small amount for bootstrap)

  console.log("\n=== Liquidity to Add ===");
  console.log("LXON amount:", ethers.formatUnits(INITIAL_LXON, 6));
  console.log("WETH amount:", ethers.formatEther(INITIAL_WETH));

  // Check balances
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  const wethBalance = await weth.balanceOf(deployerAddress);
  const ethBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  if (lxonBalance < INITIAL_LXON) {
    console.log("Insufficient LXON balance");
    return;
  }

  // Deposit ETH to get WETH if needed
  if (wethBalance < INITIAL_WETH) {
    console.log("Depositing ETH to get WETH...");
    if (ethBalance < INITIAL_WETH) {
      console.log("Insufficient ETH balance");
      return;
    }
    const depositTx = await weth["deposit()"]({ value: INITIAL_WETH });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Approve router to spend tokens
  console.log("Approving router to spend tokens...");
  await lxon.approve(await router.getAddress(), INITIAL_LXON);
  await weth.approve(await router.getAddress(), INITIAL_WETH);
  console.log("Approvals completed");

  // Add liquidity with slippage tolerance (allow up to 90% slippage for bootstrap)
  const amountLXONMin = INITIAL_LXON / 10n; // 90% slippage tolerance
  const amountWLXONMin = INITIAL_WETH / 10n; // 90% slippage tolerance
  
  const addLiquidityTx = await router.addLiquidity(
    INITIAL_LXON,
    INITIAL_WETH,
    amountLXONMin,
    amountWLXONMin,
    deployerAddress,
    Math.floor(Date.now() / 1000) + 3600
  );
  const receipt = await addLiquidityTx.wait();
  console.log("\n=== Liquidity Added Successfully ===");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Log results
  const lpBalance = await pair.balanceOf(deployerAddress);
  const [newReserve0, newReserve1] = await pair.getReserves();

  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("New LXON reserves:", ethers.formatUnits(newReserve0, 6));
  console.log("New WETH reserves:", ethers.formatEther(newReserve1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
