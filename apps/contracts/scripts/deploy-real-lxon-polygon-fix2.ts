import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🚀 Deploying REAL LXON Token on Polygon Mainnet");
  console.log("RPC: https://polygon.drpc.org");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  // Use custom RPC provider
  const provider = new ethers.JsonRpcProvider("https://polygon.drpc.org");
  const signer = new ethers.Wallet(privateKey, provider);
  
  console.log("Deployer address:", signer.address);
  console.log("Checking balance...");

  const balance = await provider.getBalance(signer.address);
  console.log("MATIC balance:", ethers.formatEther(balance), "MATIC");

  if (balance < ethers.parseEther("0.01")) {
    console.log("❌ Insufficient MATIC balance. Need at least 0.01 MATIC for deployment.");
    return;
  }

  // Deploy the actual LXON contract
  console.log("\nDeploying LXON Settlement Asset contract...");
  const LXON = await ethers.getContractFactory("LXON");
  const lxon = await LXON.connect(signer).deploy(signer.address);
  
  console.log("Transaction hash:", lxon.deploymentTransaction().hash);
  console.log("Waiting for confirmation...");
  
  await lxon.waitForDeployment();
  const lxonAddress = await lxon.getAddress();
  
  console.log("✅ LXON token deployed:", lxonAddress);
  console.log("\nToken details:");
  console.log("  Name:", await lxon.name());
  console.log("  Symbol:", await lxon.symbol());
  console.log("  Decimals:", await lxon.decimals());
  console.log("  Total Supply:", ethers.formatUnits(await lxon.totalSupply(), 6), "LXON");

  // Set up roles
  console.log("\nSetting up roles...");
  const MINT_ROLE = await lxon.MINT_ROLE();
  const ORACLE_ROLE = await lxon.ORACLE_ROLE();
  
  // Grant MINT_ROLE to deployer
  const grantMintTx = await lxon.connect(signer).grantRole(MINT_ROLE, signer.address);
  await grantMintTx.wait();
  console.log("✅ MINT_ROLE granted to deployer");

  // Grant ORACLE_ROLE to deployer
  const grantOracleTx = await lxon.connect(signer).grantRole(ORACLE_ROLE, signer.address);
  await grantOracleTx.wait();
  console.log("✅ ORACLE_ROLE granted to deployer");

  // Set reserve ceiling for minting (set to 1B USD = 100B cents)
  console.log("\nSetting reserve ceiling to 1B USD...");
  const ceilingTx = await lxon.connect(signer).updateCeiling(100000000000, ethers.ZeroHash);
  await ceilingTx.wait();
  console.log("✅ Reserve ceiling set to 1B USD");

  // Mint initial supply for liquidity
  console.log("\nMinting initial supply for liquidity...");
  const mintAmount = ethers.parseUnits("10000000", 0); // 10M LXON
  const mintTx = await lxon.connect(signer).mint(signer.address, mintAmount, ethers.ZeroHash);
  await mintTx.wait();
  console.log("✅ Minted 10M LXON to deployer");

  // Verify balance
  const balanceLxon = await lxon.balanceOf(signer.address);
  console.log("Deployer LXON balance:", ethers.formatUnits(balanceLxon, 6), "LXON");

  console.log("\n=== Deployment Complete ===");
  console.log("LXON Token Address:", lxonAddress);
  console.log("\nAdd this to .env:");
  console.log(`POLYGON_LXON_ADDRESS=${lxonAddress}`);
  console.log(`POLYGON_RPC_URL=https://polygon.drpc.org`);
  console.log("\n⚠️  PRODUCTION DEPLOYMENT - Real LXON token is now live on Polygon mainnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
