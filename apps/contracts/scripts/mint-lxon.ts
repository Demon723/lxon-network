import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🪙 Minting 1000 LXON to Wallet");
  console.log("");

  // Get private keys
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const walletPrivateKey = process.env.YOUR_WALLET_PRIVATE_KEY;
  
  if (!deployerPrivateKey || !walletPrivateKey) {
    throw new Error("Missing private keys in environment variables");
  }

  const deployer = new ethers.Wallet(deployerPrivateKey, ethers.provider);
  const wallet = new ethers.Wallet(walletPrivateKey, ethers.provider);

  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const walletAddress = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b";

  console.log("Deployer address:", deployer.address);
  console.log("Target wallet:", walletAddress);

  // Connect to LXON token - use standard ERC20 interface
  const erc20ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function transfer(address, uint256) returns (bool)",
    "function mint(address, uint256)",
    "function mintTo(address, uint256)",
    "function owner() view returns (address)",
    "function hasRole(bytes32, address) view returns (bool)",
    "function grantRole(bytes32, address)",
    "function MINTER_ROLE() view returns (bytes32)"
  ];
  
  const lxonToken = new ethers.Contract(lxonTokenAddress, erc20ABI, deployer);

  // Check owner
  try {
    const owner = await lxonToken.owner();
    console.log("Owner:", owner);
    console.log("Deployer is owner:", owner.toLowerCase() === deployer.address.toLowerCase());
  } catch (e) {
    console.log("No owner() function - likely standard ERC20");
  }

  // Try to mint using different mint function names
  const amount = ethers.parseUnits("1000", 6); // 1000 LXON (6 decimals based on earlier check)
  console.log("\nAttempting to mint 1000 LXON to", walletAddress);

  try {
    // Try mint function
    const mintTx = await lxonToken.mint(walletAddress, amount);
    console.log("Transaction hash:", mintTx.hash);
    await mintTx.wait();
    console.log("✅ Mint successful");
  } catch (error: any) {
    console.log("mint() failed:", error.message);

    try {
      // Try mintTo function
      const mintToTx = await lxonToken.mintTo(walletAddress, amount);
      console.log("Transaction hash:", mintToTx.hash);
      await mintToTx.wait();
      console.log("✅ MintTo successful");
    } catch (error2: any) {
      console.log("mintTo() failed:", error2.message);
      console.log("\n❌ Unable to mint - no mint function available");
      console.log("  The deployed token may not have a mint function or requires different permissions");
      return;
    }
  }

  // Verify balance
  const balance = await lxonToken.balanceOf(walletAddress);
  console.log("\nNew LXON balance:", ethers.formatUnits(balance, 6), "LXON");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
