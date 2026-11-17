import { ethers } from "hardhat";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Checking Ethereum Mainnet readiness for Uniswap V2 liquidity");
  console.log("Account:", deployerAddress);

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 1n) {
    console.log("\n⚠️  WARNING: Not on Ethereum Mainnet (Chain ID 1)");
    console.log("Current chain ID:", network.chainId);
    console.log("This script requires Ethereum Mainnet (Chain ID 1)");
    return;
  }

  // Check ETH balance
  const ethBalance = await ethers.provider.getBalance(deployerAddress);
  console.log("\n=== Balances ===");
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  // Required for liquidity
  const REQUIRED_ETH = ethers.parseEther("10.5"); // 10.5 WETH
  const ETH_PRICE = 3000;
  const REQUIRED_VALUE = Number(ethers.formatEther(REQUIRED_ETH)) * ETH_PRICE;

  console.log("\n=== Requirements ===");
  console.log("Required ETH:", ethers.formatEther(REQUIRED_ETH), "ETH");
  console.log("Required value: $", REQUIRED_VALUE);
  console.log("Current ETH balance: $", Number(ethers.formatEther(ethBalance)) * ETH_PRICE);

  if (ethBalance < REQUIRED_ETH) {
    console.log("\n❌ INSUFFICIENT ETH BALANCE");
    console.log("You need:", ethers.formatEther(REQUIRED_ETH), "ETH (~$", REQUIRED_VALUE, ")");
    console.log("You have:", ethers.formatEther(ethBalance), "ETH (~$", Number(ethers.formatEther(ethBalance)) * ETH_PRICE, ")");
    console.log("\nPlease add ETH to your account to proceed");
  } else {
    console.log("\n✅ SUFFICIENT ETH BALANCE");
    console.log("You have enough ETH for liquidity provision");
  }

  // Check if LXON exists on Ethereum Mainnet
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  
  try {
    const code = await ethers.provider.getCode(LXON_ADDRESS);
    if (code === "0x") {
      console.log("\n⚠️  LXON contract not found on Ethereum Mainnet");
      console.log("LXON is deployed on LXON chain (Chain ID 724)");
      console.log("You need to either:");
      console.log("1. Bridge LXON from LXON chain to Ethereum Mainnet");
      console.log("2. Deploy LXON on Ethereum Mainnet");
      console.log("3. Use a different network (BSC/Polygon)");
    } else {
      console.log("\n✅ LXON contract found on Ethereum Mainnet");
      const lxonBalance = await ethers.provider.getBalance(LXON_ADDRESS);
      console.log("LXON supply:", ethers.formatEther(lxonBalance));
    }
  } catch (error) {
    console.log("\n⚠️  Could not check LXON contract on Ethereum Mainnet");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
