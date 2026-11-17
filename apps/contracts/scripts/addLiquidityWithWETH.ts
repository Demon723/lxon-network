import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding initial liquidity with account:", deployerAddress);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Contract addresses from deployment
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0x32FfD676029494c6Cf9166dae6152EFaA51ee1D7";
  const ROUTER_ADDRESS = "0x92F4D1236026F23967eBd213547FE18606AE8dD5";

  // Initial liquidity amounts - using smaller amounts for initial bootstrap
  const INITIAL_LXON = ethers.parseUnits("100", 6); // 100 LXON (6 decimals)
  const INITIAL_WETH = ethers.parseEther("0.1"); // 0.1 WETH (18 decimals)

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

  // Check LXON balance
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

  if (lxonBalance < INITIAL_LXON) {
    console.log("Insufficient LXON balance. Need:", ethers.formatUnits(INITIAL_LXON, 6));
    console.log("Current:", ethers.formatUnits(lxonBalance, 6));
    return;
  }

  // Check WETH balance
  const wethBalance = await weth.balanceOf(deployerAddress);
  console.log("WETH balance:", ethers.formatEther(wethBalance));

  if (wethBalance < INITIAL_WETH) {
    console.log("Insufficient WETH balance. Need:", ethers.formatEther(INITIAL_WETH));
    console.log("Current:", ethers.formatEther(wethBalance));
    console.log("Depositing ETH to get WETH...");
    
    const ethBalance = await ethers.provider.getBalance(deployerAddress);
    console.log("ETH balance:", ethers.formatEther(ethBalance));
    
    if (ethBalance < INITIAL_WETH) {
      console.log("Insufficient ETH balance to deposit");
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

  // Add initial liquidity
  console.log("Adding initial liquidity...");
  console.log("LXON amount:", ethers.formatUnits(INITIAL_LXON, 6));
  console.log("WETH amount:", ethers.formatEther(INITIAL_WETH));
  
  const addLiquidityTx = await router.addLiquidity(
    INITIAL_LXON,
    INITIAL_WETH,
    INITIAL_LXON,  // amountLXONMin
    INITIAL_WETH, // amountWLXONMin
    deployerAddress,     // to
    Math.floor(Date.now() / 1000) + 3600 // deadline
  );
  const receipt = await addLiquidityTx.wait();
  console.log("Liquidity added successfully");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Log results
  const lpBalance = await pair.balanceOf(deployerAddress);
  const [reserve0, reserve1] = await pair.getReserves();

  console.log("\n=== Initial Liquidity Added Successfully ===");
  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("LXON reserves:", ethers.formatUnits(reserve0, 6));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  console.log("Current price:", ethers.formatEther(reserve1) + " WETH per LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
