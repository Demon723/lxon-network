import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

async function main() {
  console.log("=== Attempting LXON Mainnet Deployment ===\n");

  // Use the test private key to attempt deployment
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  const provider = new ethers.JsonRpcProvider("http://16.171.20.249:8545");
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log("Deployer address:", wallet.address);
  console.log("Deployer balance:", ethers.formatEther(await provider.getBalance(wallet.address)));

  try {
    // Attempt 1: Deploy WETH9
    console.log("\n=== Attempting WETH9 Deployment ===");
    const WETH9 = await ethers.getContractFactory("WETH9");
    const weth = await WETH9.connect(wallet).deploy();
    console.log("WETH9 deployment transaction:", weth.deploymentTransaction()?.hash);
    
    const wethReceipt = await weth.deploymentTransaction()?.wait();
    if (wethReceipt) {
      console.log("✅ WETH9 deployed successfully!");
      const wethAddress = await weth.getAddress();
      console.log("WETH9 address:", wethAddress);
      
      // If successful, continue with other contracts
      console.log("\n=== Attempting LXON Deployment ===");
      const LXON = await ethers.getContractFactory("LXON");
      const lxon = await LXON.connect(wallet).deploy(wallet.address);
      console.log("LXON deployment transaction:", lxon.deploymentTransaction()?.hash);
      
      const lxonReceipt = await lxon.deploymentTransaction()?.wait();
      if (lxonReceipt) {
        console.log("✅ LXON deployed successfully!");
        const lxonAddress = await lxon.getAddress();
        console.log("LXON address:", lxonAddress);
        
        // Save addresses
        const deploymentAddresses = {
          WETH_ADDRESS: wethAddress,
          LXON_ADDRESS: lxonAddress,
          DEPLOYER: wallet.address,
          DEPLOYMENT_TIMESTAMP: new Date().toISOString(),
          NETWORK: "LXON mainnet"
        };
        
        const fs = require('fs');
        fs.writeFileSync(
          './deployments/lxon-mainnet.json',
          JSON.stringify(deploymentAddresses, null, 2)
        );
        console.log("\n✅ Deployment addresses saved to deployments/lxon-mainnet.json");
        
        console.log("\n=== Deployment Successful ===");
        console.log("You can now continue with Pair and Router deployment");
      }
    }
  } catch (error) {
    console.error("\n❌ Deployment failed:", error.message);
    
    if (error.message.includes("insufficient funds")) {
      console.log("\n=== Issue: Insufficient Funds ===");
      console.log("The deployer account has no LXON for gas fees.");
      console.log("Options:");
      console.log("1. Fund the account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
      console.log("2. Use a different account with funds");
      console.log("3. Contact LXON team for testnet funds");
    } else if (error.message.includes("eth_sendRawTransaction")) {
      console.log("\n=== Issue: Transaction Format ===");
      console.log("LXON does not support standard EVM transactions.");
      console.log("This confirms the need for LXON-specific deployment method.");
    } else {
      console.log("\n=== Unknown Error ===");
      console.log("Error details:", error);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });