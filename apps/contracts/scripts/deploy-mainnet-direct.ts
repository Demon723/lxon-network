import { ethers } from "hardhat";

async function main() {
  console.log("Deploying LXON contracts to mainnet...");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("DEPLOYER_PRIVATE_KEY environment variable not set");
  }

  const rpcUrl = "http://13.51.158.120:8546";
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  // ✅ FIX: Use appropriate gas price based on chain
  const network = await provider.getNetwork();
  let gasPrice;
  if (network.chainId === 724) {
    // LXON mainnet - 20 gwei
    gasPrice = ethers.BigNumber.from("20000000000");
  } else if (network.chainId === 1) {
    // Ethereum mainnet
    gasPrice = ethers.BigNumber.from("50000000000");
  } else {
    // Testnet/goerli etc.
    gasPrice = ethers.BigNumber.from("1000000000");
  }
  console.log("Using gas price:", ethers.formatUnits(gasPrice, "gwei"), "gwei");
  console.log("Deployer address:", wallet.address);

  const balance = await provider.getBalance(wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "LXON");

  if (balance === 0n) {
    throw new Error("Deployer has no balance");
  }

  console.log("Deploying LXON Token...");
  const LXON = await ethers.getContractFactory("LXON");
  const lxonToken = await LXON.deploy();
  await lxonToken.waitForDeployment();
  const lxonAddress = await lxonToken.getAddress();
  console.log("LXON Token deployed to:", lxonAddress);

  console.log("Deploying LXON Hardened...");
  const LXONHardened = await ethers.getContractFactory("LXONHardened");
  const lxonHardened = await LXONHardened.deploy(wallet.address, 2 * 24 * 60 * 60);
  await lxonHardened.waitForDeployment();
  const hardenedAddress = await lxonHardened.getAddress();
  console.log("LXON Hardened deployed to:", hardenedAddress);

  console.log("Deploying Vesting Escrow...");
  const VestingEscrow = await ethers.getContractFactory("VestingEscrow");
  const vestingEscrow = await VestingEscrow.deploy(lxonAddress);
  await vestingEscrow.waitForDeployment();
  const vestingAddress = await vestingEscrow.getAddress();
  console.log("Vesting Escrow deployed to:", vestingAddress);

  console.log("\nDeployment Summary:");
  console.log("==================");
  console.log("LXON Token:", lxonAddress);
  console.log("LXON Hardened:", hardenedAddress);
  console.log("Vesting Escrow:", vestingAddress);
  console.log("==================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });