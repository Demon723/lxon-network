import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔄 Transferring LXON from 1B Wallet to Deployer");
  console.log("");

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const oneBPrivateKey = process.env.LXON_1B_PRIVATE_KEY;
  
  if (!deployerPrivateKey || !oneBPrivateKey) {
    throw new Error("Missing private keys in environment variables");
  }

  const deployer = new ethers.Wallet(deployerPrivateKey, ethers.provider);
  const oneBWallet = new ethers.Wallet(oneBPrivateKey, ethers.provider);

  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const erc20ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function transfer(address, uint256) returns (bool)",
  ];

  const lxonToken = new ethers.Contract(lxonTokenAddress, erc20ABI, oneBWallet);

  console.log("1B Wallet:", oneBWallet.address);
  console.log("Deployer:", deployer.address);

  // Check 1B wallet balance
  const balance = await lxonToken.balanceOf(oneBWallet.address);
  console.log("1B Wallet LXON balance:", ethers.formatUnits(balance, 6), "LXON");

  // Transfer 100 LXON
  const amount = ethers.parseUnits("100", 6); // 100 LXON (6 decimals)
  console.log("\nTransferring 100 LXON to deployer...");

  const transferTx = await lxonToken.transfer(deployer.address, amount);
  console.log("Transaction hash:", transferTx.hash);
  await transferTx.wait();
  console.log("✅ Transfer confirmed");

  // Verify new balances
  const newOneBBalance = await lxonToken.balanceOf(oneBWallet.address);
  const newDeployerBalance = await lxonToken.balanceOf(deployer.address);

  console.log("\nNew balances:");
  console.log("  1B Wallet:", ethers.formatUnits(newOneBBalance, 6), "LXON");
  console.log("  Deployer:", ethers.formatUnits(newDeployerBalance, 6), "LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
