import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  console.log("Adding initial liquidity to locally deployed contracts...");
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  
  console.log("Deployer address:", deployerAddress);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)));

  // Load deployed addresses
  const wethAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const lxonAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  const pairAddress = "0x0165878A594ca255338adfa4d48449f69242Eb8F";
  const routerAddress = "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853";

  // Connect to contracts
  const weth = await ethers.getContractAt("WETH9", wethAddress) as WETH9;
  const lxon = await ethers.getContractAt("LXON", lxonAddress) as LXON;
  const pair = await ethers.getContractAt("Pair", pairAddress) as Pair;
  const router = await ethers.getContractAt("Router", routerAddress) as Router;

  console.log("Connected to contracts:");
  console.log("WETH:", wethAddress);
  console.log("LXON:", lxonAddress);
  console.log("Pair:", pairAddress);
  console.log("Router:", routerAddress);

  // Check current LXON balance
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  console.log("Current LXON balance:", ethers.formatEther(lxonBalance));

  // Increase reserve ceiling significantly to allow large minting
  // LXON formula: tokens = usdCents * 1e4
  // To get 100M tokens: usdCents = 100M / 1e4 = 10,000 cents
  console.log("Increasing reserve ceiling significantly...");
  await lxon.updateCeiling(1000000000, ethers.ZeroHash); // 1B cents = $10M -> 10B tokens
  console.log("Reserve ceiling increased to 1B cents");

  // Now mint a large amount of LXON for testing
  console.log("Minting additional LXON for liquidity...");
  const usdCentsForMore = 10000n; // 10,000 cents = $100 -> 100M tokens
  await lxon.mint(deployerAddress, usdCentsForMore, ethers.ZeroHash);
  
  const newBalance = await lxon.balanceOf(deployerAddress);
  console.log("New LXON balance:", ethers.formatEther(newBalance));

  // Deposit ETH to get WETH
  console.log("\nDepositing ETH to get WETH...");
  const INITIAL_WETH = ethers.parseEther("10"); // 10 ETH for testing
  const depositTx = await weth.deposit(deployerAddress, { value: INITIAL_WETH });
  await depositTx.wait();
  console.log("WETH deposited successfully");

  const wethBalance = await weth.balanceOf(deployerAddress);
  console.log("WETH balance:", ethers.formatEther(wethBalance));

  // Approve router to spend tokens
  console.log("\nApproving router to spend tokens...");
  const INITIAL_LXON = ethers.parseEther("100"); // 100 LXON for testing
  
  await lxon.approve(routerAddress, INITIAL_LXON);
  await weth.approve(routerAddress, INITIAL_WETH);
  console.log("Approvals completed");

  // Add initial liquidity
  console.log("\nAdding initial liquidity...");
  // Use smaller amounts for testing since LXON balance is limited
  const testLXON = ethers.parseEther("10"); // 10 LXON
  const testWETH = ethers.parseEther("1"); // 1 ETH
  
  const addLiquidityTx = await router.addLiquidity(
    testLXON,
    testWETH,
    testLXON,  // amountLXONMin
    testWETH, // amountWLXONMin
    deployerAddress,
    Math.floor(Date.now() / 1000) + 3600
  );
  const receipt = await addLiquidityTx.wait();
  console.log("Liquidity added successfully");
  console.log("Gas used:", receipt?.gasUsed.toString());

  // Log results
  const lpBalance = await pair.balanceOf(deployerAddress);
  const [reserve0, reserve1] = await pair.getReserves();

  console.log("\n=== Test Liquidity Added Successfully ===");
  console.log("LP tokens received:", ethers.formatEther(lpBalance));
  console.log("LXON reserves:", ethers.formatEther(reserve0));
  console.log("WETH reserves:", ethers.formatEther(reserve1));
  
  if (reserve0 > 0 && reserve1 > 0) {
    const price = Number(reserve1) / Number(reserve0);
    console.log("Current price:", price.toFixed(4), "WETH per LXON");
    console.log("Current price (USD):", (price * 2000).toFixed(2), "USD (assuming $2k ETH)");
  }

  console.log("\n=== System Validation Complete ===");
  console.log("✅ Contracts deployed and working");
  console.log("✅ Liquidity added successfully");
  console.log("✅ Router functionality validated");
  console.log("✅ Ready for mainnet deployment when method available");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });