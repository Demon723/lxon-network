import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Deploying fixed Pair and migrating liquidity");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const OLD_PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  // Connect to old contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const oldPair = (await ethers.getContractAt("Pair", OLD_PAIR_ADDRESS)) as Pair;

  console.log("\n=== Current State (Old Pair) ===");
  const oldReserve0 = await oldPair.reserve0();
  const oldReserve1 = await oldPair.reserve1();
  const oldLXONBalance = await lxon.balanceOf(OLD_PAIR_ADDRESS);
  const oldWETHBalance = await weth.balanceOf(OLD_PAIR_ADDRESS);
  const oldLPBalance = await oldPair.balanceOf(deployerAddress);

  console.log("Old Pair WETH reserve:", ethers.formatEther(oldReserve0));
  console.log("Old Pair LXON reserve:", ethers.formatUnits(oldReserve1, 6));
  console.log("Old Pair WETH balance:", ethers.formatEther(oldWETHBalance));
  console.log("Old Pair LXON balance:", ethers.formatUnits(oldLXONBalance, 6));
  console.log("Deployer LP balance:", ethers.formatEther(oldLPBalance));

  // Deploy new fixed Pair
  console.log("\n=== Deploying New Fixed Pair ===");
  const PairFactory = await ethers.getContractFactory("Pair");
  const newPair = await PairFactory.deploy(WETH_ADDRESS, LXON_ADDRESS) as Pair;
  await newPair.waitForDeployment();
  const newPairAddress = await newPair.getAddress();

  console.log("New Pair deployed to:", newPairAddress);
  console.log("Transaction hash:", newPair.deploymentTransaction()?.hash);

  // Deploy new Router
  console.log("\n=== Deploying New Router ===");
  const RouterFactory = await ethers.getContractFactory("Router");
  const newRouter = await RouterFactory.deploy(WETH_ADDRESS, LXON_ADDRESS, newPairAddress) as Router;
  await newRouter.waitForDeployment();
  const newRouterAddress = await newRouter.getAddress();

  console.log("New Router deployed to:", newRouterAddress);
  console.log("Transaction hash:", newRouter.deploymentTransaction()?.hash);

  // Remove liquidity from old pair
  console.log("\n=== Removing Liquidity from Old Pair ===");
  const burnTx = await oldPair.burn(deployerAddress);
  await burnTx.wait();
  console.log("Liquidity removed from old pair");

  // Check deployer balances after burn
  const deployerLXONAfter = await lxon.balanceOf(deployerAddress);
  const deployerWETHAfter = await weth.balanceOf(deployerAddress);
  console.log("Deployer LXON after burn:", ethers.formatUnits(deployerLXONAfter, 6));
  console.log("Deployer WETH after burn:", ethers.formatEther(deployerWETHAfter));

  // Transfer tokens to new pair
  console.log("\n=== Transferring Tokens to New Pair ===");
  const transferLXONTx = await lxon.transfer(newPairAddress, deployerLXONAfter);
  await transferLXONTx.wait();
  console.log("LXON transferred to new pair");

  const transferWETHTx = await weth.transfer(newPairAddress, deployerWETHAfter);
  await transferWETHTx.wait();
  console.log("WETH transferred to new pair");

  // Mint LP tokens in new pair
  console.log("\n=== Minting LP Tokens in New Pair ===");
  const mintTx = await newPair.mint(deployerAddress);
  await mintTx.wait();
  console.log("LP tokens minted in new pair");

  // Verify new state
  console.log("\n=== New Pair State ===");
  const newReserve0 = await newPair.reserve0();
  const newReserve1 = await newPair.reserve1();
  const newLXONBalance = await lxon.balanceOf(newPairAddress);
  const newWETHBalance = await weth.balanceOf(newPairAddress);
  const newLPBalance = await newPair.balanceOf(deployerAddress);

  console.log("New Pair WETH reserve:", ethers.formatEther(newReserve0));
  console.log("New Pair LXON reserve:", ethers.formatUnits(newReserve1, 6));
  console.log("New Pair WETH balance:", ethers.formatEther(newWETHBalance));
  console.log("New Pair LXON balance:", ethers.formatUnits(newLXONBalance, 6));
  console.log("Deployer LP balance:", ethers.formatEther(newLPBalance));

  // Calculate price
  const ETH_PRICE_USD = 3000;
  const wethReserve = Number(ethers.formatEther(newReserve0));
  const lxonReserve = Number(ethers.formatUnits(newReserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;

  console.log("\n=== Price ===");
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD.toFixed(2));
  console.log("Target price: $1.50");

  console.log("\n=== Contract Addresses ===");
  console.log("Old Pair:", OLD_PAIR_ADDRESS);
  console.log("New Pair:", newPairAddress);
  console.log("New Router:", newRouterAddress);
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);

  console.log("\n=== NEXT STEPS ===");
  console.log("1. Update frontend to use new Pair address:", newPairAddress);
  console.log("2. Update frontend to use new Router address:", newRouterAddress);
  console.log("3. Test swaps with new Router");
  console.log("4. Apply to exchanges with new DEX addresses");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
