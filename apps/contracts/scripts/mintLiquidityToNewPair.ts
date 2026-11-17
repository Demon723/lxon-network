import { ethers } from "hardhat";
import { Pair } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Minting LP tokens for existing balances in new Pair");
  console.log("Account:", deployerAddress);

  const NEW_PAIR_ADDRESS = "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08";
  const newPair = (await ethers.getContractAt("Pair", NEW_PAIR_ADDRESS)) as Pair;

  console.log("\nMinting LP tokens...");
  const mintTx = await newPair.mint(deployerAddress);
  const receipt = await mintTx.wait();
  console.log("LP tokens minted successfully");
  console.log("Transaction hash:", receipt?.hash);

  // Check final state
  const [reserve0, reserve1] = await newPair.getReserves();
  const lpBalance = await newPair.balanceOf(deployerAddress);

  console.log("\n=== Final State ===");
  console.log("Reserve0 (WETH):", ethers.formatEther(reserve0));
  console.log("Reserve1 (LXON):", ethers.formatUnits(reserve1, 6));
  console.log("LP tokens received:", ethers.formatEther(lpBalance));

  // Calculate price
  const ETH_PRICE_USD = 3000;
  const wethReserve = Number(ethers.formatEther(reserve0));
  const lxonReserve = Number(ethers.formatUnits(reserve1, 6));
  const pricePerLXON = wethReserve / lxonReserve;
  const priceUSD = pricePerLXON * ETH_PRICE_USD;
  const tvlUSD = (lxonReserve * priceUSD) + (wethReserve * ETH_PRICE_USD);

  console.log("\n=== Price Calculation ===");
  console.log("Price per LXON:", pricePerLXON, "WETH");
  console.log("Price per LXON: $", priceUSD.toFixed(2));
  console.log("TVL: $", tvlUSD.toFixed(2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
