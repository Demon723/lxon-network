import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔍 Investigating Missing LXON Balances");
  console.log("");

  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // Known LXON token addresses to check
  const tokenAddresses = [
    "0xc0177883C0c662870855660495C697385FE040f5", // Current .env address
    "0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c", // Old WETH address from some scripts
    "0x3aD52bD5996f16C902225b0d9C111fafE6B77786", // Old pair address
  ];

  // Known addresses that should have balances
  const addressesToCheck = [
    "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27", // Deployer
    "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b", // 1B LXON wallet
    "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3", // Founder
  ];

  const erc20ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
  ];

  console.log("=== Checking Token Contracts ===\n");

  for (const tokenAddress of tokenAddresses) {
    console.log(`Checking token: ${tokenAddress}`);

    try {
      const token = new ethers.Contract(tokenAddress, erc20ABI, provider);
      const code = await provider.getCode(tokenAddress);

      if (code === "0x") {
        console.log("  ❌ No contract deployed at this address\n");
        continue;
      }

      const name = await token.name();
      const symbol = await token.symbol();
      const decimals = await token.decimals();
      const totalSupply = await token.totalSupply();

      console.log(`  Name: ${name}`);
      console.log(`  Symbol: ${symbol}`);
      console.log(`  Decimals: ${decimals}`);
      console.log(`  Total Supply: ${ethers.formatUnits(totalSupply, decimals)}`);

      console.log("\n  Balances by address:");
      for (const addr of addressesToCheck) {
        const balance = await token.balanceOf(addr);
        const formatted = ethers.formatUnits(balance, decimals);
        console.log(`    ${addr}: ${formatted}`);
      }
      console.log("");

    } catch (error: any) {
      console.log(`  ❌ Error: ${error.message}\n`);
    }
  }

  console.log("\n=== Looking for deployment scripts that might have replaced the token ===\n");

  // Check for recent deployments
  console.log("This investigation should check:");
  console.log("1. When was the current token contract deployed?");
  console.log("2. Was a new token contract deployed during PQC integration?");
  console.log("3. Are there multiple token contracts with the same address?");
  console.log("4. Did the token address in .env change?");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
