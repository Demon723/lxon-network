import { ethers } from "hardhat";

async function main() {
  console.log("Deploying LXON Settlement Asset Contract...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "ETH");

  if (balance === 0n) {
    throw new Error("Deployer has no balance. Please get ETH from faucet or use funded account.");
  }

  console.log("Deploying LXON Settlement Asset...");
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const lxon = await LXONSettlementAsset.deploy(deployer.address);
  await lxon.waitForDeployment();
  const lxonAddress = await lxon.getAddress();
  console.log("LXON Settlement Asset deployed to:", lxonAddress);

  // Setup roles for the Value Growth Plan
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));

  console.log("\nSetting up governance roles...");
  console.log("MINT_ROLE (3-of-5 validator multi-sig): needs to be granted to validator multi-sig");
  console.log("ORACLE_ROLE (attestation oracle): needs to be granted to oracle address");
  console.log("GUARDIAN_ROLE (2-of-5 emergency pause): needs to be granted to guardian multi-sig");

  console.log("\nDeployment Summary:");
  console.log("==================");
  console.log("LXON Settlement Asset:", lxonAddress);
  console.log("Admin:", deployer.address);
  console.log("Chain ID:", (await ethers.provider.getNetwork()).chainId);
  console.log("Network:", await ethers.provider.getNetwork().then(n => n.name));
  console.log("==================");

  console.log("\nNext Steps:");
  console.log("1. Grant MINT_ROLE to 3-of-5 validator multi-sig");
  console.log("2. Grant ORACLE_ROLE to attestation oracle");
  console.log("3. Grant GUARDIAN_ROLE to 2-of-5 guardian multi-sig");
  console.log("4. Engage accounting firm for first attestation");
  console.log("5. Set initial reserve ceiling via updateCeiling()");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });