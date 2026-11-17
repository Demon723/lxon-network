import { ethers } from "hardhat";

async function main() {
  console.log("=== Checking Previously Deployed LXON Production RPC ===\n");

  // The production RPC from successful deployment
  const productionRPC = "http://13.51.158.120:8546";
  const testRPC = "http://16.171.20.249:8545";

  console.log("Testing Production RPC:", productionRPC);
  console.log("Testing Current RPC:", testRPC);
  console.log();

  // Test production RPC
  try {
    const prodProvider = new ethers.JsonRpcProvider(productionRPC);
    const prodNetwork = await prodProvider.getNetwork();
    const prodBlockNumber = await prodProvider.getBlockNumber();
    
    console.log("✅ Production RPC Response:");
    console.log("  Chain ID:", prodNetwork.chainId.toString());
    console.log("  Block Number:", prodBlockNumber);
    console.log("  Network Name:", prodNetwork.name);
  } catch (error) {
    console.log("❌ Production RPC Error:", error.message);
  }

  console.log();

  // Test current RPC
  try {
    const testProvider = new ethers.JsonRpcProvider(testRPC);
    const currentNetwork = await testProvider.getNetwork();
    const currentBlockNumber = await testProvider.getBlockNumber();
    
    console.log("✅ Current RPC Response:");
    console.log("  Chain ID:", currentNetwork.chainId.toString());
    console.log("  Block Number:", currentBlockNumber);
    console.log("  Network Name:", currentNetwork.name);
  } catch (error) {
    console.log("❌ Current RPC Error:", error.message);
  }

  console.log("\n=== Checking Deployer Balance on Production RPC ===");
  try {
    const prodProvider = new ethers.JsonRpcProvider(productionRPC);
    const deployerAddress = "0x098Ae030804120Def93880a303788d24dc600d00";
    const balance = await prodProvider.getBalance(deployerAddress);
    console.log("Deployer balance:", ethers.formatEther(balance), "LXON");
  } catch (error) {
    console.log("Balance check error:", error.message);
  }

  console.log("\n=== Checking for Previously Deployed Contracts ===");
  try {
    const prodProvider = new ethers.JsonRpcProvider(productionRPC);
    
    // Check for previously deployed contracts
    const previousAddresses = {
      WETH: "0x4F90ddD66C2616DC8870F7f7B94b3e0247068ad4",
      LXON: "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c",
      Pair: "0xac86E2dE13eAC876ED8872b76BBAa10e2c1050cC",
      Router: "0xEF4ce5C29dD14fE2A342F0BC38D5A1cEBD500e6C"
    };

    for (const [name, address] of Object.entries(previousAddresses)) {
      try {
        const code = await prodProvider.getCode(address);
        if (code.length > 2) {
          console.log(`✅ ${name} contract exists at ${address}`);
        } else {
          console.log(`❌ ${name} contract NOT found at ${address}`);
        }
      } catch (error) {
        console.log(`⚠️ ${name} check error:`, error.message);
      }
    }
  } catch (error) {
    console.log("Contract check error:", error.message);
  }

  console.log("\n=== Conclusion ===");
  console.log("If production RPC is working and contracts exist:");
  console.log("1. Update .env to use production RPC");
  console.log("2. Use existing deployed contracts");
  console.log("3. Add liquidity to existing pair");
  console.log("4. Deploy price floor mechanism");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });