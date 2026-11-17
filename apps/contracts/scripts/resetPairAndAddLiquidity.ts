import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Resetting pair and adding fresh liquidity");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7";
  const ROUTER_ADDRESS = "0x92F4D1236026F23967eBd213547FE18606AE8dD5";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", ROUTER_ADDRESS)) as Router;

  // Check current state
  const [reserve0, reserve1] = await pair.getReserves();
  const lpSupply = await pair.totalSupply();
  const lpBalance = await pair.balanceOf(deployerAddress);

  console.log("\n=== Current Pair State ===");
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Total LP supply:", ethers.formatEther(lpSupply));
  console.log("Your LP balance:", ethers.formatEther(lpBalance));

  // If there's LP tokens, remove the existing liquidity
  if (lpBalance > 0n) {
    console.log("\n=== Removing Existing Liquidity ===");
    
    // Approve router to burn LP tokens
    await pair.approve(await router.getAddress(), lpBalance);
    console.log("Approved router to burn LP tokens");

    // Remove liquidity
    const removeTx = await router.removeLiquidity(
      lpBalance,
      0, // amountLXONMin (allow any)
      0, // amountWLXONMin (allow any)
      deployerAddress,
      Math.floor(Date.now() / 1000) + 3600
    );
    await removeTx.wait();
    console.log("Existing liquidity removed");
    console.log("Transaction hash:", removeTx.hash);
  }

  // Add fresh liquidity
  console.log("\n=== Adding Fresh Liquidity ===");
  
  const INITIAL_LXON = ethers.parseUnits("100", 6); // 100 LXON
  const INITIAL_WETH = ethers.parseEther("0.1"); // 0.1 WETH

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

  // Add fresh liquidity
  const addLiquidityTx = await router.addLiquidity(
    INITIAL_LXON,
    INITIAL_WETH,
    INITIAL_LXON / 2n,  // 50% slippage tolerance
    INITIAL_WETH / 2n, // 50% slippage tolerance
    deployerAddress,
    Math.floor(Date.now() / 1000) + 3600
  );
  const receipt = await addLiquidityTx.wait();
  console.log("\n=== Liquidity Added Successfully ===");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Log final state
  const newLpBalance = await pair.balanceOf(deployerAddress);
  const [newReserve0, newReserve1] = await pair.getReserves();

  console.log("LP tokens received:", ethers.formatEther(newLpBalance));
  console.log("New LXON reserves:", ethers.formatUnits(newReserve0, 6));
  console.log("New WETH reserves:", ethers.formatEther(newReserve1));
  console.log("Current price:", ethers.formatEther(newReserve1) + " WETH per LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
