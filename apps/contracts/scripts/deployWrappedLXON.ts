import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Wrapped LXON to Ethereum Mainnet");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");
  
  if (balance < ethers.parseEther("0.1")) {
    console.log("⚠️  WARNING: Low ETH balance for deployment");
    console.log("Recommended: At least 0.1 ETH for gas fees");
  }
  
  console.log("\n=== Deploying Wrapped LXON ===");
  const WrappedLXON = await ethers.getContractFactory("WrappedLXON");
  const wrappedLXON = await WrappedLXON.deploy();
  await wrappedLXON.waitForDeployment();
  
  const address = await wrappedLXON.getAddress();
  console.log("✅ Wrapped LXON deployed to:", address);
  console.log("Network: Ethereum Mainnet (Chain ID 1)");
  console.log("Token Name: Wrapped LXON");
  console.log("Token Symbol: wLXON");
  
  console.log("\n=== Next Steps ===");
  console.log("1. Verify contract on Etherscan");
  console.log("2. Set bridge operator (your multi-sig recommended)");
  console.log("3. Lock 20,900 LXON on LXON chain");
  console.log("4. Mint 20,900 wLXON on Ethereum Mainnet");
  console.log("5. Add liquidity to Uniswap V2");
  
  console.log("\n=== Contract Addresses ===");
  console.log("wLXON:", address);
  console.log("Deployer:", deployer.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
