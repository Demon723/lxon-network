import { ethers } from "hardhat";
import { WETH9, LXON, Pair, Router } from "../typechain-types";
import * as fs from 'fs';

async function main() {
  console.log("=== LXON Contract Deployment Verification ===\n");

  // Load deployment addresses from file or use environment variables
  let deploymentAddresses: any;
  
  try {
    const deploymentData = fs.readFileSync('./deployments/fresh-contracts.json', 'utf8');
    deploymentAddresses = JSON.parse(deploymentData);
    console.log("Loaded addresses from deployments/fresh-contracts.json");
  } catch (error) {
    console.log("Using environment variables instead");
    deploymentAddresses = {
      WETH_ADDRESS: process.env.WETH_ADDRESS,
      LXON_ADDRESS: process.env.LXON_ADDRESS,
      PAIR_ADDRESS: process.env.PAIR_ADDRESS,
      ROUTER_ADDRESS: process.env.ROUTER_ADDRESS,
      DEPLOYER: process.env.DEPLOYER
    };
  }

  const provider = ethers.provider;
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deployer address:", deployerAddress);
  console.log("Network:", await provider.getNetwork());
  console.log("Block:", await provider.getBlockNumber());

  // Verify each contract
  console.log("\n--- Contract Verification ---");

  // WETH9
  if (deploymentAddresses.WETH_ADDRESS) {
    console.log("\n1. WETH9 Contract:", deploymentAddresses.WETH_ADDRESS);
    try {
      const wethCode = await provider.getCode(deploymentAddresses.WETH_ADDRESS);
      console.log("   Code exists:", wethCode.length > 2);
      
      if (wethCode.length > 2) {
        const weth = await ethers.getContractAt("WETH9", deploymentAddresses.WETH_ADDRESS) as WETH9;
        const wethBalance = await weth.balanceOf(deployerAddress);
        console.log("   Deployer WETH balance:", ethers.formatEther(wethBalance));
      }
    } catch (error) {
      console.log("   Error:", error);
    }
  }

  // LXON
  if (deploymentAddresses.LXON_ADDRESS) {
    console.log("\n2. LXON Contract:", deploymentAddresses.LXON_ADDRESS);
    try {
      const lxonCode = await provider.getCode(deploymentAddresses.LXON_ADDRESS);
      console.log("   Code exists:", lxonCode.length > 2);
      
      if (lxonCode.length > 2) {
        const lxon = await ethers.getContractAt("LXON", deploymentAddresses.LXON_ADDRESS) as LXON;
        const lxonBalance = await lxon.balanceOf(deployerAddress);
        console.log("   Deployer LXON balance:", ethers.formatEther(lxonBalance));
        
        const totalSupply = await lxon.totalSupply();
        console.log("   Total supply:", ethers.formatEther(totalSupply));
        
        const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
        const hasMintRole = await lxon.hasRole(MINT_ROLE, deployerAddress);
        console.log("   Has MINT_ROLE:", hasMintRole);
        
        const reserveCeiling = await lxon.reserveCeiling();
        console.log("   Reserve ceiling:", reserveCeiling.toString());
      }
    } catch (error) {
      console.log("   Error:", error);
    }
  }

  // Pair
  if (deploymentAddresses.PAIR_ADDRESS) {
    console.log("\n3. Pair Contract:", deploymentAddresses.PAIR_ADDRESS);
    try {
      const pairCode = await provider.getCode(deploymentAddresses.PAIR_ADDRESS);
      console.log("   Code exists:", pairCode.length > 2);
      
      if (pairCode.length > 2) {
        const pair = await ethers.getContractAt("Pair", deploymentAddresses.PAIR_ADDRESS) as Pair;
        
        const token0 = await pair.token0();
        const token1 = await pair.token1();
        console.log("   Token0:", token0);
        console.log("   Token1:", token1);
        
        const [reserve0, reserve1] = await pair.getReserves();
        console.log("   Reserve0 (LXON):", ethers.formatEther(reserve0));
        console.log("   Reserve1 (WETH):", ethers.formatEther(reserve1));
        
        const lpBalance = await pair.balanceOf(deployerAddress);
        console.log("   Deployer LP balance:", ethers.formatEther(lpBalance));
        
        if (reserve0 > 0 && reserve1 > 0) {
          const price = Number(reserve1) / Number(reserve0);
          console.log("   Current price:", price.toFixed(4), "WETH per LXON");
          console.log("   Current price (USD):", (price * 2000).toFixed(2), "USD (assuming $2k ETH)");
        }
      }
    } catch (error) {
      console.log("   Error:", error);
    }
  }

  // Router
  if (deploymentAddresses.ROUTER_ADDRESS) {
    console.log("\n4. Router Contract:", deploymentAddresses.ROUTER_ADDRESS);
    try {
      const routerCode = await provider.getCode(deploymentAddresses.ROUTER_ADDRESS);
      console.log("   Code exists:", routerCode.length > 2);
      
      if (routerCode.length > 2) {
        const router = await ethers.getContractAt("Router", deploymentAddresses.ROUTER_ADDRESS) as Router;
        
        const weth = await router.weth();
        const lxon = await router.lxon();
        const pair = await router.pair();
        
        console.log("   WETH in Router:", weth);
        console.log("   LXON in Router:", lxon);
        console.log("   Pair in Router:", pair);
      }
    } catch (error) {
      console.log("   Error:", error);
    }
  }

  console.log("\n=== Verification Complete ===");
  console.log("\nNext steps:");
  console.log("1. If contracts exist: Update .env with verified addresses");
  console.log("2. If liquidity exists: Price should be near $1.50 target");
  console.log("3. If no liquidity: Use web wallet to add liquidity");
  console.log("4. Deploy price floor mechanism when ready");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });