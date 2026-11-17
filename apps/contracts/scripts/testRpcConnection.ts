import { ethers } from "hardhat";

async function main() {
  console.log("Testing RPC connection...");
  
  const provider = ethers.provider;
  const network = await provider.getNetwork();
  console.log("Network:", network);
  
  const blockNumber = await provider.getBlockNumber();
  console.log("Current block:", blockNumber);
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log("Deployer address:", deployerAddress);
  console.log("Deployer balance:", ethers.formatEther(await provider.getBalance(deployerAddress)));
  
  // Test contract connection
  const LXON_ADDRESS = process.env.LXON_ADDRESS || "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c";
  console.log("Testing LXON contract at:", LXON_ADDRESS);
  
  try {
    const code = await provider.getCode(LXON_ADDRESS);
    console.log("Contract code length:", code.length);
    console.log("Contract exists:", code.length > 2);
  } catch (error) {
    console.error("Error checking contract:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });