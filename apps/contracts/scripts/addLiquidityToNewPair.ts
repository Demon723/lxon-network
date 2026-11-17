import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding liquidity to new fixed Pair");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";
  const NEW_ROUTER_ADDRESS = "0xA2AF542999c4412E387ba7e3867cE541cdfeDb80";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const newPair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;
  const newRouter = (await ethers.getContractAt("Router", NEW_ROUTER_ADDRESS)) as Router;

  // Target: $1.50 per LXON, TVL $62,700
  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000;
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD;

  // Check deployer balances
  const deployerLXONBalance = await lxon.balanceOf(deployerAddress);
  const deployerWETHBalance = await weth.balanceOf(deployerAddress);
  const deployerETHBalance = await ethers.provider.getBalance(deployerAddress);

  // Target amounts - adjust based on available LXON
  const availableLXON = Number(ethers.formatUnits(deployerLXONBalance, 6));
  const TARGET_LXON = Math.floor(availableLXON);
  const TARGET_WETH = TARGET_LXON * TARGET_WETH_PER_LXON;

  console.log("\n=== Target Liquidity ===");
  console.log("Target LXON:", TARGET_LXON);
  console.log("Target WETH:", TARGET_WETH);
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");

  console.log("\n=== Deployer Balances ===");
  console.log("LXON:", ethers.formatUnits(deployerLXONBalance, 6));
  console.log("WETH:", ethers.formatEther(deployerWETHBalance));
  console.log("ETH:", ethers.formatEther(deployerETHBalance));

  const lxonAmount = ethers.parseUnits(TARGET_LXON.toString(), 6);
  const wethAmount = ethers.parseEther(TARGET_WETH.toString());

  // Deposit ETH to get WETH if needed
  if (deployerWETHBalance < wethAmount) {
    const wethNeeded = wethAmount - deployerWETHBalance;
    console.log("\nDepositing ETH to get WETH...");
    console.log("WETH needed:", ethers.formatEther(wethNeeded));
    if (deployerETHBalance < wethNeeded) {
      console.log("ERROR: Insufficient ETH balance");
      return;
    }
    const depositTx = await weth["deposit()"]({ value: wethNeeded });
    await depositTx.wait();
    console.log("WETH deposited successfully");
  }

  // Transfer tokens to new pair
  console.log("\nTransferring tokens to new pair...");
  await lxon.transfer(NEW_PAIR_ADDRESS, lxonAmount);
  await weth.transfer(NEW_PAIR_ADDRESS, wethAmount);
  console.log("Tokens transferred");

  // Mint LP tokens
  console.log("\nMinting LP tokens...");
  const mintTx = await newPair.mint(deployerAddress);
  const receipt = await mintTx.wait();
  console.log("LP tokens minted successfully");
  console.log("Transaction hash:", receipt?.hash);

  // Verify final state
  const finalLXONBalance = await lxon.balanceOf(NEW_PAIR_ADDRESS);
  const finalWETHBalance = await weth.balanceOf(NEW_PAIR_ADDRESS);
  const [reserve0, reserve1] = await newPair.getReserves();
  const lpBalance = await newPair.balanceOf(deployerAddress);

  console.log("\n=== Final State ===");
  console.log("Pair LXON balance:", ethers.formatUnits(finalLXONBalance, 6));
  console.log("Pair WETH balance:", ethers.formatEther(finalWETHBalance));
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));
  console.log("LP tokens received:", ethers.formatEther(lpBalance));

  // Calculate price
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;
  const tvlUSD = (lxonReserve * priceUSD) + (wethReserve * ETH_PRICE_USD);

  console.log("\n=== Price Calculation ===");
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD.toFixed(2));
  console.log("Target price: $", TARGET_PRICE_USD);
  console.log("Price deviation:", ((priceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");
  console.log("TVL: $", tvlUSD.toFixed(2));

  console.log("\n=== Contract Addresses ===");
  console.log("New Pair:", NEW_PAIR_ADDRESS);
  console.log("New Router:", NEW_ROUTER_ADDRESS);
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);

  console.log("\n=== Status ===");
  if (Math.abs(priceUSD - TARGET_PRICE_USD) < 0.01) {
    console.log("✅ PRICE TARGET ACHIEVED");
  } else {
    console.log("❌ PRICE TARGET NOT ACHIEVED");
  }

  if (reserve0.toString() === finalWETHBalance.toString() && reserve1.toString() === finalLXONBalance.toString()) {
    console.log("✅ RESERVES SYNCED WITH BALANCES");
  } else {
    console.log("❌ RESERVES NOT SYNCED WITH BALANCES");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
