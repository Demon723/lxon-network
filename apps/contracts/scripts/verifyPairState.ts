import { ethers } from "hardhat";
import { WETH9, LXON, Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";

  console.log("Verifying Pair state after liquidity addition");
  console.log("Account:", deployerAddress);

  // Contract addresses
  const WETH_ADDRESS = "0x007696cdF0Bf860823126D72C8e3D52448B5285E";
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const PAIR_ADDRESS = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";

  // Connect to contracts
  const weth = (await ethers.getContractAt("WETH9", WETH_ADDRESS)) as WETH9;
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  const pair = (await ethers.getContractAt("Pair", PAIR_ADDRESS)) as Pair;

  const ETH_PRICE_USD = 3000;
  const TARGET_PRICE_USD = 1.5;

  console.log("\n=== Token Order ===");
  const token0 = await pair.token0();
  const token1 = await pair.token1();
  console.log("token0:", token0);
  console.log("token1:", token1);
  console.log("token0 is WETH:", token0.toLowerCase() === WETH_ADDRESS.toLowerCase());
  console.log("token1 is LXON:", token1.toLowerCase() === LXON_ADDRESS.toLowerCase());

  console.log("\n=== Actual Token Balances ===");
  const wethBalance = await weth.balanceOf(PAIR_ADDRESS);
  const lxonBalance = await lxon.balanceOf(PAIR_ADDRESS);
  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));

  console.log("\n=== Pair Reserves ===");
  const [reserve0, reserve1] = await pair.getReserves();
  console.log("Reserve0 (raw):", reserve0.toString());
  console.log("Reserve1 (raw):", reserve1.toString());
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));

  console.log("\n=== Price Calculation ===");
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;
  const tvlUSD = (lxonReserve * priceUSD) + (wethReserve * ETH_PRICE_USD);

  console.log("WETH reserve:", wethReserve);
  console.log("LXON reserve:", lxonReserve);
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD.toFixed(2));
  console.log("Target price: $", TARGET_PRICE_USD);
  console.log("Price deviation:", ((priceUSD - TARGET_PRICE_USD) / TARGET_PRICE_USD * 100).toFixed(2), "%");
  console.log("TVL: $", tvlUSD.toFixed(2));

  console.log("\n=== LP Token Supply ===");
  const totalSupply = await pair.totalSupply();
  const deployerLPBalance = await pair.balanceOf(deployerAddress);
  console.log("Total LP supply:", ethers.formatEther(totalSupply));
  console.log("Deployer LP balance:", ethers.formatEther(deployerLPBalance));

  console.log("\n=== Contract Addresses ===");
  console.log("Pair:", PAIR_ADDRESS);
  console.log("Router: 0x0De021F0caA907e11f06a2bd78767b1a3557D8A3");
  console.log("WETH:", WETH_ADDRESS);
  console.log("LXON:", LXON_ADDRESS);

  console.log("\n=== Status ===");
  if (Math.abs(priceUSD - TARGET_PRICE_USD) < 0.01) {
    console.log("✅ PRICE TARGET ACHIEVED");
  } else {
    console.log("❌ PRICE TARGET NOT ACHIEVED");
  }

  if (reserve0.toString() === wethBalance.toString() && reserve1.toString() === lxonBalance.toString()) {
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
