import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deploying new Pair and adding liquidity");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const ROUTER_ADDRESS = "0x92F4D1236026F23967eBd213547FE18606AE8dD5";

  // Connect to existing contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const router = (await ethers.getContractAt("Router", ROUTER_ADDRESS)) as Router;

  // Deploy new Pair
  console.log("\n=== Deploying New Pair ===");
  const PairFactory = await ethers.getContractFactory("Pair");
  const newPair = await PairFactory.deploy(WETH_ADDRESS, LXON_ADDRESS);
  await newPair.waitForDeployment();
  const newPairAddress = await newPair.getAddress();
  console.log("New Pair deployed to:", newPairAddress);

  // Get the Pair contract's owner (Router) and update it
  // Actually, we need to update the Router to use the new Pair
  // But Router is immutable. We'll need to deploy a new Router too.
  
  console.log("\n=== Deploying New Router ===");
  const RouterFactory = await ethers.getContractFactory("Router");
  const newRouter = await RouterFactory.deploy(WETH_ADDRESS, LXON_ADDRESS, newPairAddress);
  await newRouter.waitForDeployment();
  const newRouterAddress = await newRouter.getAddress();
  console.log("New Router deployed to:", newRouterAddress);

  // Add liquidity
  console.log("\n=== Adding Liquidity ===");
  
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

  // Approve new router to spend tokens
  console.log("Approving new router to spend tokens...");
  await lxon.approve(newRouterAddress, INITIAL_LXON);
  await weth.approve(newRouterAddress, INITIAL_WETH);
  console.log("Approvals completed");

  // Add liquidity
  const addLiquidityTx = await newRouter.addLiquidity(
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
  const lpBalance = await newPair.balanceOf(deployerAddress);
  const [reserve0, reserve1] = await newPair.getReserves();

  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Current price:", ethers.formatEther(reserve1) + " WETH per LXON");

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
