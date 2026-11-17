const { ethers } = require("hardhat");
const dotenv = require("dotenv");
dotenv.config();

async function main() {
  console.log("=== Mint 111.6M WETH ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const wethAddress = process.env.WETH_MINTABLE;
  console.log("WETH Mintable address:", wethAddress);

  const WETH9Mintable = await ethers.getContractFactory("WETH9Mintable");
  const weth = WETH9Mintable.attach(wethAddress);

  const amountToMint = ethers.parseEther("111600000"); // 111.6M WETH

  console.log("Minting 111.6M WETH to:", deployer.address);

  const tx = await weth.mint(deployer.address, amountToMint);
  console.log("Transaction:", tx.hash);
  await tx.wait();
  console.log("✅ Successfully minted 111.6M WETH!");

  const balance = await weth.balanceOf(deployer.address);
  console.log("New WETH balance:", ethers.formatEther(balance), "WETH");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
