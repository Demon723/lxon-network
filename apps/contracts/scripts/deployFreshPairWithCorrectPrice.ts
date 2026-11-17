import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deploying fresh Pair with correct $1.50 price");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";

  // Connect to existing contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

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

  // Deploy fresh Pair
  console.log("\n=== Deploying Fresh Pair ===");
  const PairFactory = await ethers.getContractFactory("Pair");
  const newPair = await PairFactory.deploy(WETH_ADDRESS, LXON_ADDRESS);
  await newPair.waitForDeployment();
  const newPairAddress = await newPair.getAddress();
  console.log("New Pair deployed to:", newPairAddress);

  // Deploy fresh Router
  console.log("\n=== Deploying Fresh Router ===");
  const RouterFactory = await ethers.getContractFactory("Router");
  const newRouter = await RouterFactory.deploy(WETH_ADDRESS, LXON_ADDRESS, newPairAddress);
  await newRouter.waitForDeployment();
  const newRouterAddress = await newRouter.getAddress();
  console.log("New Router deployed to:", newRouterAddress);

  // Calculate correct liquidity amounts for $1.50 price
  const LXON_AMOUNT = ethers.parseUnits("10000", 6); // 10,000 LXON
  const WETH_AMOUNT = ethers.parseEther("5"); // 5 WETH (at $3,000 ETH = $15,000)

  console.log("\n=== Adding Liquidity ===");
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
    return;
  }

  // Deposit ETH to get WETH if needed
  if (wethBalance < WETH_AMOUNT) {
    console.log("Depositing ETH to get WETH...");
    const wethNeeded = WETH_AMOUNT - wethBalance;
    if (ethBalance < wethNeeded) {
      console.log("Insufficient ETH balance. Need:", ethers.formatEther(wethNeeded));
      console.log("Current:", ethers.formatEther(ethBalance));
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Approve new router to spend tokens
  console.log("Approving new router to spend tokens...");
  await lxon.approve(newRouterAddress, LXON_AMOUNT);
  await weth.approve(newRouterAddress, WETH_AMOUNT);
  console.log("Approvals completed");

  // Add liquidity to fresh pair (first liquidity, so reserves are 0)
  const addLiquidityTx = await newRouter.addLiquidity(
    LXON_AMOUNT,
    WETH_AMOUNT,
    LXON_AMOUNT, // No slippage for first liquidity
    WETH_AMOUNT, // No slippage for first liquidity
    deployerAddress,
    Math.floor(Date.now() / 1000) + 3600
  );
  const receipt = await addLiquidityTx.wait();
  console.log("\n=== Liquidity Added Successfully ===");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Log final state
  const lpBalance = await newPair.balanceOf(deployerAddress);
  const [reserve0, reserve1] = await newPair.getReserves();

  const newPrice = reserve0 > 0n ? Number(reserve1) / Number(reserve0) : 0;
  const newPriceUSD = newPrice * ETH_PRICE_USD;

  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Price:", newPrice, "WETH per LXON");
  console.log("Price: $", newPriceUSD, "per LXON");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Price deviation:", ((newPriceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");

  console.log("\n=== New Contract Addresses ===");
  console.log("New Pair:", newPairAddress);
  console.log("New Router:", newRouterAddress);
  console.log("\n⚠️  IMPORTANT: Update your frontend and documentation to use the new Router address!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
