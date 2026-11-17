import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding liquidity to achieve $1.50 price floor");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xfFa1E7758fb857e31f87CFCc23cDC597C1800615";
  const ROUTER_ADDRESS = "0xB99527140C52ef7110F35853E4a497966d908338";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;
  const router = (await ethers.getContractAt("Router", ROUTER_ADDRESS)) as Router;

  // Target price: $1.50 per LXON
  // Assuming ETH/WETH is ~$3,000
  // Target: 1 LXON = $1.50 = 0.0005 WETH (since $1.50 / $3,000 = 0.0005)
  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000; // Approximate ETH price
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD; // 0.0005 WETH per LXON

  console.log("\n=== Price Target ===");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("ETH price: $", ETH_PRICE_USD);
  console.log("Target WETH per LXON:", TARGET_WETH_PER_LXON);

  // Check current reserves
  const [reserve0, reserve1] = await pair.getReserves();
  const lpSupply = await pair.totalSupply();
  const lpBalance = await pair.balanceOf(deployerAddress);

  console.log("\n=== Current Pair State ===");
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Total LP supply:", ethers.formatEther(lpSupply));
  console.log("Your LP balance:", ethers.formatEther(lpBalance));

  // Calculate current price
  const currentPrice = reserve0 > 0n ? Number(reserve1) / Number(reserve0) : 0;
  const currentPriceUSD = currentPrice * ETH_PRICE_USD;
  console.log("Current price:", currentPrice, "WETH per LXON");
  console.log("Current price: $", currentPriceUSD, "per LXON");

  // Calculate the correct liquidity amounts for $1.50 price
  // We need to add enough liquidity to override the current small reserves
  // Current reserves are: 100 LXON and 0.0000000001 WETH
  // We want to add: 10,000 LXON and 5 WETH (which will significantly shift the price)
  
  const LXON_AMOUNT = ethers.parseUnits("10000", 6); // 10,000 LXON
  const WETH_AMOUNT = ethers.parseEther("5"); // 5 WETH (at $3,000 ETH = $15,000)

  console.log("\n=== Adding Correct Liquidity ===");
  console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
  console.log("WETH amount:", ethers.formatEther(WETH_AMOUNT));
  console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");

  // Check balances
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  const wethBalance = await weth.balanceOf(deployerAddress);
  const ethBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  if (lxonBalance < LXON_AMOUNT) {
    console.log("Insufficient LXON balance. Need:", ethers.formatUnits(LXON_AMOUNT, 6));
    console.log("Current:", ethers.formatUnits(lxonBalance, 6));
    console.log("You need to mint or transfer more LXON");
    return;
  }

  // Deposit ETH to get WETH if needed
  if (wethBalance < WETH_AMOUNT) {
    console.log("Depositing ETH to get WETH...");
    const wethNeeded = WETH_AMOUNT - wethBalance;
    if (ethBalance < wethNeeded) {
      console.log("Insufficient ETH balance. Need:", ethers.formatEther(wethNeeded));
      console.log("Current:", ethers.formatEther(ethBalance));
      console.log("You need to add more ETH to your account");
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Approve router to spend tokens
  console.log("Approving router to spend tokens...");
  await lxon.approve(await router.getAddress(), LXON_AMOUNT);
  await weth.approve(await router.getAddress(), WETH_AMOUNT);
  console.log("Approvals completed");

  // Add liquidity with slippage tolerance
  // Since current reserves are very small, adding significant liquidity will override the price
  const addLiquidityTx = await router.addLiquidity(
    LXON_AMOUNT,
    WETH_AMOUNT,
    0, // Allow any slippage since we're overriding the price
    0, // Allow any slippage since we're overriding the price
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

  const newPrice = newReserve0 > 0n ? Number(newReserve1) / Number(newReserve0) : 0;
  const newPriceUSD = newPrice * ETH_PRICE_USD;

  console.log("LP tokens received:", ethers.formatEther(newLpBalance));
  console.log("New LXON reserves:", ethers.formatUnits(newReserve0, 6));
  console.log("New WETH reserves:", ethers.formatEther(newReserve1));
  console.log("New price:", newPrice, "WETH per LXON");
  console.log("New price: $", newPriceUSD, "per LXON");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Price deviation:", ((newPriceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
