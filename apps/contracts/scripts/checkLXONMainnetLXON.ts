import { ethers } from "hardhat";
import { LXON } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Checking LXON on LXON Mainnet (Chain ID 724)");
  console.log("Account:", deployerAddress);

  // LXON contract on LXON chain
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 724n) {
    console.log("\n⚠️  WARNING: Not on LXON Mainnet (Chain ID 724)");
    console.log("Current chain ID:", network.chainId);
    console.log("This script requires LXON Mainnet (Chain ID 724)");
    return;
  }

  // Check LXON balance
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  const ethBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  // Check total supply
  const totalSupply = await lxon.totalSupply();
  console.log("\n=== Token Info ===");
  console.log("Total supply:", ethers.formatUnits(totalSupply, 6));
  console.log("Your percentage:", (Number(ethers.formatUnits(lxonBalance, 6)) / Number(ethers.formatUnits(totalSupply, 6)) * 100).toFixed(2), "%");

  // Check if we have enough to bridge
  const BRIDGE_AMOUNT = ethers.parseUnits("20900", 6); // 20,900 LXON
  console.log("\n=== Bridge Requirements ===");
  console.log("Amount to bridge:", ethers.formatUnits(BRIDGE_AMOUNT, 6));
  console.log("Your balance:", ethers.formatUnits(lxonBalance, 6));

  if (lxonBalance < BRIDGE_AMOUNT) {
    console.log("\n❌ INSUFFICIENT LXON BALANCE");
    console.log("You need:", ethers.formatUnits(BRIDGE_AMOUNT, 6), "LXON");
    console.log("You have:", ethers.formatUnits(lxonBalance, 6), "LXON");
    console.log("\nYou'll need to get more LXON from the old deployer or mint more");
  } else {
    console.log("\n✅ SUFFICIENT LXON BALANCE");
    console.log("You have enough LXON to bridge to Ethereum Mainnet");
  }

  console.log("\n=== Next Steps ===");
  console.log("1. Set up a bridge from LXON chain to Ethereum Mainnet");
  console.log("2. Bridge 20,900 LXON to Ethereum Mainnet");
  console.log("3. Add liquidity to Uniswap V2 on Ethereum Mainnet");
  console.log("4. This keeps your native token on LXON chain + liquidity on Ethereum Mainnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
