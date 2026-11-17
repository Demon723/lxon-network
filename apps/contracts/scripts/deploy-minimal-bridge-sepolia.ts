import { ethers } from "hardhat";

async function main() {
  console.log("🧪 Deploying Minimal Bridge on Sepolia");
  console.log("======================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  const chainId = 11155111;

  console.log("Deploying MinimalBridge...");
  const Bridge = await ethers.getContractFactory("MinimalBridge");
  const bridge = await Bridge.deploy(chainId, {
    gasLimit: 1000000,
    gasPrice: ethers.parseUnits("10", "gwei"),
  });
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  console.log("✅ Minimal Bridge deployed:", bridgeAddress);

  console.log("\nTesting basic functions...");
  const chainIdCheck = await bridge.chainId();
  console.log("Chain ID:", chainIdCheck.toString());

  const founder = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";
  await (await bridge.addSigner(founder)).wait();
  console.log("✅ Added founder as signer:", founder);

  console.log("\n✅✅✅ Minimal Bridge Test Passed ✅✅✅");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
